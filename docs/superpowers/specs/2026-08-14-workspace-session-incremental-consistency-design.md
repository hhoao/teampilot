# 设计:工作区/会话数据增量一致性(mutation 后不再全量重扫)

日期:2026-08-14
状态:已评审待实现

## 背景与问题

### 现象

创建/删除 workspace、创建/删除/置顶/改名 session 等任何 mutation 后,`ChatCubit` 都会调 `SessionDataStore.loadWorkspaceData` 做**全量重扫**(14 个 workspace 的 manifest + 456 个 session.json)。

实测日志:

```
[boot] SessionDataStore.loadWorkspaceData 14 workspaces (+2883ms) 456 sessions (+49ms) total=2932ms
```

### 根因(已排查确认)

1. `loadWorkspaces()` → `_readManifest(indexOnly: false)` 对每个 session 串行执行 2 次 async 文件操作(`fs.stat` + `fs.readString` + jsonDecode),只为计算 `Workspace.sessionIds`(按 createdAt 排序)。在 UI isolate 繁忙时(debug 构建、终端渲染),每次 await 事件循环周转约 4ms,343 个 session 的 workspace 耗时 2.8s。
2. 第一层修复(已合入):`listSessionIdsForWorkspace` 对 LocalFilesystem 走同步快路径(`SessionSnapshotReader.readSessionMapsSync`),全量重扫降为 ~500ms(debug)。但**架构问题仍在**:每次 mutation 都 O(全量) 重扫,复杂度随数据量增长,且 `WorkspaceIndexStore.upsert/remove`(磁盘快照增量维护)已写好但从未接线,`_workspacesIndexByRoot` 内存缓存永不失效。

### 已确认的事实(研究结论)

- **session.json 唯一写入方是 `SessionRepository`**(唯一原语 `SessionRepositoryFs.writeText`,14 个 mutation 复用 `_writeSession`);CLI 进程只写 `runtime/{tool}/` 目录,TeamBus 只写 `bus/mail`、`bus/tasks`,automation/extension 零写操作。
- **manifest.json 不持久化 sessionIds**(`_writeManifest` 写盘前置空),sessionIds 仅是内存/快照概念。
- mutation 方法大多**已返回新对象**(`createWorkspace` → `Workspace`、`updateWorkspaceMetadata` → `Workspace?`、`createSession` → `(AppSession, Workspace)`、`cloneWorkspace` → `(Workspace, List<AppSession>)`、`remapWorkspaceTarget` → `(Workspace, List<AppSession>)`),但全量重扫把返回值全部丢弃。
- `WorkspaceIndexStore.upsert/remove` 无任何调用者;index 文件只在 `loadWorkspacesIndex` 的 rebuild / stale-revalidate 时重写。
- boot 常规路径(`hydrateNativeHomeIndex` / `bootstrapHomeIndex`)已经是快路径(`loadWorkspaceIndex` + 按需 `loadSessionsForWorkspace`);`loadWorkspaceData` 只在 `reloadAll`(home/SSH 切换)与 mutation 后调用。
- `_withInferredMemberPlacementInit` 是读时内存迁移(不落盘),不重扫只是 flag 持久化时机推迟,无数据丢失风险。
- `WorkspaceCatalog` 是未接线的平行实现(生产零实例化),不在本设计范围内。

### 决策

采用**增量一致性**架构:repository 的 mutation 返回值作为唯一真相源,`SessionDataStore` 在内存增量 patch 快照,`WorkspaceIndexStore` 增量维护磁盘快照;全量重扫仅保留给 `reloadAll`(存储后端切换)。单实例前提(同一时间只有一个 TeamPilot 写数据),无需外部变更检测。

## Section 1:SessionDataStore 增量 API(核心)

`SessionDataStore`(session_data_store.dart)新增纯内存增量方法,全部返回新 `ChatDataSnapshot`;`ChatCubit` 直接 `_emitSnapshot`,不再调 `loadWorkspaceData`:

| 方法 | 输入 | 语义 |
|---|---|---|
| `snapshotWithWorkspace(Workspace)` | mutation 返回值 | 新增或替换 workspace(保留其 `sessionIds` 不变) |
| `snapshotWithSession(AppSession)` | mutation 返回值 | 新增或替换 session;新 session 按其 `createdAt` 插入对应 workspace 的 `sessionIds`(desc 序) |
| `snapshotWithoutSession(String sessionId)` | 删除的 id | 从 sessions 移除 + 从所属 workspace 的 `sessionIds` 移除 |
| `snapshotWithoutWorkspace(String workspaceId)` | 删除的 id | 移除 workspace + 其全部 sessions 及其 `sessionIds` 条目 |
| `snapshotWithWorkspaceAndSessions(Workspace, List<AppSession>)` | remap/clone 返回值 | 替换 workspace + 替换该 workspace 的 sessions 列表 + 重建其 `sessionIds`(按 createdAt desc) |

### sessionIds 维护规则(统一)

- 新 session 插入:`sessionIds` 保持 createdAt desc(与全量重建一致),即新 session 排在头部(其 createdAt 必然最新);为稳妥按 createdAt 二分插入。
- 替换 session:顺序不变。
- 全量路径(`loadWorkspaceData` / `loadWorkspaceIndex`)仍由 repository 提供 sessionIds,顺序同为 createdAt desc(见 Section 2 的统一)。

### 现有方法调整

- `loadWorkspaceData` 保留,仅供 `reloadAll` 使用(语义不变:全量重建 + `_markAllWorkspacesHydrated`)。
- `createWorkspaceWithFirstSession` / `addWorkspaceDirectory` / `updateWorkspaceMetadata` / `applyWorkspaceIcon` / `importCustomWorkspaceIcon` / `deleteSessionRecord` / `deleteWorkspaceRecord` / `cloneWorkspace` 改为:执行 repository mutation → 用返回值调增量方法 → 返回快照(签名不变,调用方零改动)。

## Section 2:SessionRepository index 增量维护

`SessionRepository`(session_repository.dart)的每个写操作在返回前维护磁盘快照 `workspaces-index.json` + 内存缓存 `_workspacesIndexByRoot`:

1. **新增内部辅助** `_rememberWorkspace(Workspace)` / `_forgetWorkspace(String id)`:
   - 更新 `_workspacesIndexByRoot[缓存键]` 中对应条目(替换/移除),缓存键与 `_workspacesIndexCacheKey()` 一致;
   - 异步(或同步)调 `WorkspaceIndexStore.upsert/remove` 写盘。
2. **接入点**(写 manifest 或影响 workspace 状态的方法):
   - `createWorkspace`、`updateWorkspaceMetadata`、`applyWorkspaceIcon`、`importCustomWorkspaceIcon`、`updateWorkspaceFolders`、`updateWorkspaceMemberTargets`、`updateWorkspaceMemberPlacement` → `upsert(结果)`;
   - `createSession` → `upsert(返回的 workspace)`(sessionIds 变化);
   - `cloneWorkspace` → `upsert(新 workspace)`;
   - `deleteSession` → 读取当前快照中该 workspace 条目并 `upsert(sessionIds 去掉被删 id 的副本)`(仅在快照存在时);
   - `deleteWorkspace` → `remove(id)`。
3. **sessionIds 顺序统一**:`_loadWorkspaces(indexOnly: true)` 的 sessionIds 来源从 `listSessionDirectoryIds`(目录序)改为 `listSessionIdsForWorkspace`(createdAt 序,已走同步快路径,单 workspace ~20ms),保证 boot 快路径与全量路径顺序一致。index rebuild 是罕见路径(stale 时),成本可接受。
4. **stale 竞态修复**:seed 路径(`DefaultWorkspaceService.ensureDefault` → `repo.createWorkspace`)因 mutation 已更新缓存,`loadWorkspaceIndexAfterSeed`(app_data_bootstrap.dart:394)不再命中陈旧快照。

## Section 3:ChatCubit 与页面调用点改造

### ChatCubit(chat_cubit.dart)

| 方法 | 现状 | 改为 |
|---|---|---|
| `touchSession`(2032) | `loadWorkspaceData` 全量 | `patchSession(返回值)` |
| `toggleSessionPin`(2163) | `loadWorkspaceData` 全量 | `patchSession(返回值)` |
| `deleteSession`(2197) | 乐观移除 + `deleteSessionRecord`(内部全量) | 乐观移除 + `deleteSessionRecord`(内部改为增量 `snapshotWithoutSession`) |
| `deleteWorkspace`(2241) | 逐 session 删除 + `deleteWorkspaceRecord`(内部全量) | `deleteWorkspaceRecord` 内部改为增量 `snapshotWithoutWorkspace`;循环 `deleteSession` 保留(负责 tab 清理 + automation disable),emit 次数与现状一致(每次 deleteSession 的乐观 emit + 最终一次 workspace 移除 emit) |
| `cloneWorkspace`(2213) | `loadWorkspaceData` 全量 | `snapshotWithWorkspaceAndSessions` |

新增 `patchSession(AppSession)`(与既有 `patchWorkspace`(1474)对称):按 workspaceId 替换 sessions 中的条目,维护 sessionIds 不变。

### 页面/服务直接调用方(5 处,拿 repo 返回值 → 调 chat patch API)

| 调用点 | 现状 | 改为 |
|---|---|---|
| `workspace_folders_section.dart:85` | `updateWorkspaceFolders` + `loadWorkspaceData` | 返回值 → `chat.patchWorkspace(workspace)` |
| `workspace_folders_section.dart:119` | `remapWorkspaceTarget` + `loadWorkspaceData` | 返回值 `(Workspace, List<AppSession>)` → `chat.patchWorkspaceAndSessions(...)` |
| `mixed_workspace_member_placement_panel.dart:214` | 同上 | 同上 |
| `chat_workbench.dart:226` | 同上 | 同上 |
| `session_default_materializer.dart:96,138` | `createSession` + `loadWorkspaceData` + `_openSession` | `(AppSession, Workspace)` → `chat.patchSession(session)` + `patchWorkspace(workspace)`(顺序:先 patch 再 `_openSession`) |

`app_data_bootstrap.dart:352`(`reloadAll`)保留 `loadWorkspaceData` 不变——后端切换必须全量重建。

## Section 4:错误处理与边界

- mutation 返回 null(如 `updateWorkspaceMetadata` 找不到 workspace):不 patch、不 emit(磁盘未变,快照仍正确);现状是 emit 全量重扫结果,行为差异可接受。
- 增量方法只依赖传入值,不重新读盘;若某 mutation 未来需要磁盘状态(如 `deleteSession` 的 upsert 需要旧 sessionIds),从**内存缓存快照**(而非全量重扫)读取。
- `_withInferredMemberPlacementInit`:增量路径不触发读时迁移,依赖下次 `_readManifest` 或显式 placement save,无数据丢失。
- `touchSession` 的 unawaited 语义不变(调用方不 await),patch 本身瞬时完成。

## Section 5:测试策略

1. `SessionDataStore` 单元测试(新):
   - 每个增量方法:给定旧快照 + mutation 返回值 → 断言新快照(workspaces/sessions/visible 三视图 + sessionIds 顺序);
   - sessionIds 插入/删除边界(新 session 在最前、删除中间 id、删除 workspace 连带清理)。
2. `SessionRepository` 测试(新):mutation 后 `loadWorkspacesIndex` 返回新鲜数据(缓存 + 磁盘),seed 场景无 stale。
3. 既有测试:更新断言 `loadWorkspaceData` 调用的测试(chat_cubit_test 等)为增量语义;`workspace_catalog_test` 不动(未接线路径)。
4. 性能验证:创建 workspace 流程(createWorkspace + createSession + emit)耗时 < 50ms(debug),与 workspace/session 总数无关。

## 范围外(明确不做)

- `WorkspaceCatalog`(未接线平行实现)改造。
- `loadWorkspaceData` 在 `reloadAll` 的保留场景不动。
- 多实例/外部修改检测(单实例前提已确认)。
- `loadSessionsForWorkspace` 按需 hydration 路径不动。
