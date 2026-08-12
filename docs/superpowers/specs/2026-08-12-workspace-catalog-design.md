# WorkspaceCatalog: 工作区/会话内存单一数据源 — 设计

Date: 2026-08-12
Status: Approved (brainstorming)

## 问题

工作区创建慢。根因（按影响排序）：

1. **每次创建全量重扫库 3 次**。`createWorkspace → createSession → loadWorkspaceData` 严格串行，其中 3 处重新读取*所有*工作区 manifest 和*所有* session.json：
   - `session_repository.dart:346`（`createWorkspace` 开头；`allowDuplicate: true` 时去重逻辑被跳过但扫描照跑，纯浪费）
   - `session_repository.dart:706`（`createSession` 内重读 manifest）
   - `session_data_store.dart:260`（结尾 `loadWorkspaceData` 全量重载）
2. **所有 mutation 路径都以全量 `loadWorkspaceData` 收尾**（改名/图标/删/克隆/加目录/排序等 10+ 调用点），库越大每次操作越慢。
3. **每次写入都触发全量 index 读-改-写**（`_syncWorkspaceIndexEntry`，`session_repository.dart:185`），创建流程内出现 2 次。
4. **Trust 预置重复 git-root 遍历**。`workspace_trust_provisioner.dart:92` 中 4 个工具任务各自独立执行 `collectTrustedProjectKeys`，同一文件夹重复 3-5 次逐级 `fs.stat` 父目录（`trusted_project_paths.dart:26-43`）；且整个预置阻塞创建流程。
5. **主 isolate 同步 IO**：`WorkspaceIndexStore.upsert` 同步读+解码 index（`index_snapshot_isolate.dart:53`），本地 `listSync`/`readAsStringSync`（`session_snapshot_reader.dart:33-48`）。

代码里已有目录雏形（`WorkspaceIndexStore` 磁盘索引、`_workspacesIndexByRoot` 内存缓存、`SessionDataStore.appendSession/replaceSession/removeSession` 内存补丁、`_hydratedSessionWorkspaceIds` 懒加载追踪），但未串成完整架构。

## 架构：WorkspaceCatalog 单一数据源

**WorkspaceCatalog 成为工作区/会话的唯一 API 面**：内存状态为 UI 快照的单一事实来源，磁盘写穿保证持久性，`workspaces-index.json` 仅作 boot 快启与崩溃恢复的派生缓存。

```
WorkspaceCatalog (client/lib/services/catalog/workspace_catalog.dart)   ← 唯一 API 面
  ├─ 内存状态: List<Workspace> + List<AppSession> + hydration 集合 + scope 标志
  ├─ 快照派生: ChatDataSnapshot（可见性过滤逻辑从 SessionDataStore 移入）
  ├─ mutation 编排: 写穿 → 内存补丁 → 返回快照（所有方法统一模式）
  ├─ trust 门控: Map<workspaceId, Future> 后台预置注册表
  └─ 索引刷新: dirty 标记 + 串行防抖写 WorkspaceIndexStore
        │
        ▼
SessionRepository (瘦身: 纯实体持久化 + 领域助手)
  ├─ 实体级: createSession/ensureMemberBinding/renameSession/...（保留 LockPool）
  ├─ 团队计划: team plan / cliTeamName counter / member binding
  ├─ 启动/重载原语: loadWorkspacesIndex / loadWorkspaces / loadSessions
  └─ 删除 _syncWorkspaceIndexEntry 全量 index 重写（归 Catalog 防抖）
        │
        ▼
SessionRepositoryFs + WorkspaceIndexStore + WorkspaceTrustProvisioner (磁盘层)
```

### 职责边界

- **Catalog**：库级状态（workspaces/sessions 列表）、hydration、mutation 编排、快照派生、scope 过滤、trust 门控、index 防抖刷新、去重。
- **SessionRepository**：单实体级持久化（manifest/session.json 读写、实体锁）、团队领域逻辑（team plan、cliTeamName counter、member binding、placement）、启动/重载原语（`loadWorkspacesIndex`/`loadWorkspaces`/`loadSessions`/`loadSessionsForWorkspace`）。对"库级快照"无认知。
- **全量扫描仅两处合法调用者**：Catalog boot（索引快照路径）与 `catalog.reload()`（SSH 切 home / 重绑定后真磁盘重读）。
- 删除 `client/lib/cubits/chat/session_data_store.dart`（职责并入 Catalog）；`ChatDataSnapshot` 保留为纯值类型；`_workspacesIndexByRoot` 静态缓存并入 Catalog 实例状态（按 root key 无效化的逻辑由 Catalog 持有 repo 实例替代）。

## 设计

### 1. Mutation 统一模式

所有 mutation（创建/加目录/改名/图标/删/克隆/排序/成员目标/remap/会话字段更新…）同一骨架：

```
catalog.X(...) {
  await _mutationLock.synchronized(() async {
    updated = await _repo.X(...)          // 1. 磁盘写穿（实体锁内）
    _patchMemory(updated)                 // 2. 内存补丁
    _markIndexDirty();                    // 3. 标记脏（防抖串行落盘）
  });
  return _deriveSnapshot();               // 4. 派生快照 → ChatCubit emit
}
```

- 写穿成功后才补丁内存（磁盘写失败 → 抛错、内存不变，记 `AppLogger`）。
- 会话实体级并发：Catalog 的 `_withSession(sessionId, fn)` 锁内读**内存最新副本** → 应用变更 → 写穿 → 补丁。消除 repo 现在"每次磁盘 fresh read"与内存状态的分叉。
- 返回 `ChatDataSnapshot`（或含实体的 record），ChatCubit 保持唯一 emit 所有者。

### 2. `createWorkspaceWithFirstSession` 时序

```
t0  repo.createWorkspace: 去重查内存（allowDuplicate:false 时，零 IO）→ 写 manifest.json
t1  repo.createSession: 写 session.json
t2  内存补丁 workspace + session（即时）
t3  emit 快照 → 导航到工作区（即时）
t4  [后台] trust 预置: 一次 git-root 遍历 → 4 工具并行写（见 §3）
t5  [后台] 防抖后一次 index 写（见 §4）
```

不再有：3×全扫、2×index 重写、trust 阻塞。

### 3. Trust 预置：后台 + 启动门控

- `catalog.provisionTrust(workspaceId)`：幂等，`Map<workspaceId, Future<void>>` 去重；后台执行；失败记日志不炸 UI，允许下次 mutation/启动重试。
- `catalog.trustProvisioningFor(workspaceId)` 返回该 Future（未启动则立即启动并登记）。
- `WorkspaceTrustProvisioner` 重构：`collectTrustedProjectKeys` **计算一次**，4 个工具任务共享结果；`findCanonicalGitRoot` 的逐级父目录 `fs.stat` 改为 `Future.wait` 并行。
- `SessionLifecycleService.prepareLaunch` 在物化 CONFIG_DIR 前 `await catalog.trustProvisioningFor(workspaceId)` —— 无竞态，创建零阻塞。

### 4. 索引刷新（防抖串行）

- 磁盘 `workspaces-index.json` 保留（boot 快启仍读它），写入全归 Catalog。
- 任何 mutation 置 dirty → 单个串行 writer，防抖 300ms 批量落盘；进程内连续 mutation 只产生一次写。
- boot 的 `loadWorkspacesIndex` deferred 校验逻辑不变。
- Catalog 持有内存快照的 workspaces 列表即 index 内容源（含 `sessionIds` 目录名列表，按需从 repo 取目录名或维护增量）。

### 5. 读取与 hydration

- boot：`catalog.loadIndex()` = 磁盘索引 → 内存（保持现快路径 `repo.loadWorkspacesIndex`）。
- 会话懒加载保留：`catalog.ensureSessionsForWorkspace(workspaceId)` 加载并标记 hydrated（沿用 `_hydratedSessionWorkspaceIds` 语义）。
- Catalog 只读访问器语义（明确）：
  - `workspaces` / `sessions`：同步，内存列表快照（workspaces 常驻；sessions 仅含已 hydrated 工作区）。
  - `workspaceById(id)`：同步，内存查；未命中返回 null（workspaces 启动即全量在内存，不会 miss 于已加载数据）。
  - `sessionsForWorkspace(workspaceId)`：`Future<List<AppSession>>`，未 hydrated 时先 `ensureSessionsForWorkspace` 再返回内存副本。
  - `sessionById(id)`：同步，仅在已 hydrated 工作区内查；未命中返回 null。
- 所有现存直接读 `repo.loadSessionsForWorkspace` 的调用方改走 Catalog 访问器：`automation_dispatcher.dart:209,291`、`session_default_materializer.dart`、`workspace_page.dart:273`、`workspace_session_actions.dart:543`、`chat_workbench.dart`。

### 6. 调用面迁移

- `ChatCubit` 持 `WorkspaceCatalog`（构造注入 `SessionRepository`），去掉所有 `repo` 参数传递（`createWorkspaceWithFirstSession`/`addWorkspaceDirectory`/`updateWorkspaceMetadata`/`applyWorkspaceIcon`/`deleteSessionRecord`/`deleteWorkspaceRecord`/`cloneWorkspace` 等）。
- `app_shell.dart` / `app_data_bootstrap.dart` 构造 `WorkspaceCatalog(repo: sessionRepo)` 并注入。
- `loadWorkspaceData` 语义拆分：
  - 常规 mutation 后 = 内存快照（mutation 已返回，调用点删除多余 reload）；
  - home 切换 / SSH 重绑定 = `catalog.reload()`（真磁盘重读，`app_data_bootstrap.reloadAll` 使用）。
- 审计全部 `loadWorkspaceData` 调用点（`workspace_folders_section.dart:85,118`、`workspace_details_dialog.dart:101`、`chat_workbench.dart:225`、`mixed_workspace_member_placement_panel.dart:213`、`session_default_materializer.dart:97,139`、`chat_cubit.dart:2002,2133`、bootstrap:352）改走 mutation 返回的补丁快照或 catalog.reload。
- 页面/面板 `context.read<SessionRepository>()` 的读取处改为 `context.read<WorkspaceCatalog>()`（仅读取访问器）。

### 7. 错误处理与边界

- 磁盘写失败：mutation 抛错，内存不回滚；下次 mutation/boot 自然修复。
- 实体锁（LockPool）防止并发丢更新；mutation 级锁防止库级补丁交错。
- 防抖 writer 崩溃/异常：记日志，下次 dirty 触发重写；boot 校验兜底。
- trust 预置失败：仅日志；启动门控 await 的 Future 以错误完成时，prepareLaunch 不阻塞启动（catch 后继续），CLI 首次运行可能弹信任确认（现状等价）。
- `reload()` 期间的内存替换原子完成（单锁内 swap 列表后派生快照）。
- 会话 `sessionIds`（manifest 内）维护：`_readManifest(indexOnly:false)` 的 createdAt 排序语义保留在 repo 原语中；Catalog 补丁时对 `sessionIds` 做增量插入（新会话按 createdAt 有序插入内存列表，目录名列表由 index 防抖刷新时重列一次）。

## 测试

- Catalog 单测（构造注入 repo + `setUpTestAppStorage` / 假 FS）：
  - `createWorkspaceWithFirstSession` 全程零全扫断言（`loadWorkspaces`/`loadSessions` 未被调用，用 spy repo 或记录类）；
  - mutation → 内存补丁 → 快照断言（改名/图标/删/克隆/加目录/排序各一例）；
  - 防抖索引写：连续 3 次 mutation 只产生 1 次 `WorkspaceIndexStore.writeAll`（fake timer）；
  - `_withSession` 并发更新不丢字段（两个并发 mutation 同一 session）；
  - trust 门控幂等：两次 `provisionTrust` 只跑一次；`trustProvisioningFor` 未启动时启动并返回同一 Future。
- `WorkspaceTrustProvisioner` 单测：`collectTrustedProjectKeys` 只执行一次（注入收集函数计数）；父目录并行遍历结果与串行一致。
- 既有测试适配：`SessionDataStore` 删除后的引用更新、`ChatCubit` 签名变更、`ChatDataSnapshot` 保持。

## 验证

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

## 范围外（后续任务）

- 工作区/会话之外的库（launch profiles、automations、providers）不纳入 Catalog，保持现状。
- 远程（SSH）场景下 Catalog 的内存语义与本地一致，但 hydration 的 SFTP 批量读（16 并发）保留在 repo 原语内。
- `home_new_workspace_dialog.dart` 的 UX（创建中的加载指示）不在本设计范围；创建已近即时，无需新增。
