# 远程执行架构 · P1+P2 合并设计稿（home target 归一 + 去单例 + 控制面/工作面拆分 + 每目录 target）

> 状态：**已澄清待实现** · **最优终态、零向后兼容** · 建立在分支 `feat/p0-runtime-target` 之上
> 上游设计：[docs/remote-execution-architecture.md](../../remote-execution-architecture.md) §4/§5/§6/§8/§10/§12（P1+P2 行）
> 决策来源：2026-06-22 用户全局准则 + P1 Q1–Q6 + "P1、P2 一起做"（经 team-lead 转达）
> **本稿合并并取代** standalone P1 稿（`2026-06-22-p1-home-target-design.md`）的范围。

## 0. 全局准则

**不做向下/向后兼容、不考虑工作量、直接最优架构。** target/`homeTargetId`/context 即唯一真相源；无双写、无 schemaVersion 兼容、无"读旧迁移"；旧磁盘数据失效是用户接受的已知后果。P1+P2 顺带**清除前序所有兼容脚手架**。

## 1. 范围与分期边界

| 期 | 解锁 | 本稿覆盖 |
|---|---|---|
| **P1** | home target 归一 + 权威源反转 + 选 target UI | §2、§3 |
| **P2** | **项目远程**：去单例 + 控制面/工作面拆分 + `Workspace.folders[].targetId` 多机解析（两工作区分落 local/ssh 互不影响；远程离线项目列表仍可读） | §4–§8 |

**P2/P3 边界（重要，本稿据此设计）**：P2 = **整工作区落在一个 target**（项目远程）。**成员远程**（mixed 工作区、`AppSession.folderAssignments` 成员→目录分配、反向隧道、bus raw-socket/relay、跨机产物、`remoteOs` 探测/Windows-remote 分支）一律 **P3，不在本稿**。模型允许 folder 跨机，但 P2 的消费只到"会话按其工作区 target 解析单一工作面上下文"。

## 2. P1：home target 归一 + 权威源反转（设备本地 homeTargetId）

> 完整论证见 standalone P1 稿 §2–§4；此处给合并后的终态结论。

- **home 身份是 bootstrap-local 事实**：home target 选择存**设备本地 SharedPrefs**（`HomeTargetStore`，key `flashskyai.home_target.v1`）为**唯一权威**。原因：控制面永远在 home（§5），home 的身份不能存在 home 之上；Android home=ssh 时 targets.json 在远程，要连远程须先在本地知道 home → 自指循环。故 `homeTargetId` 必须本地。（已经 team-lead 确认采用本地 homeTargetId。）
- `homeTargetId` ∈ `'local' | 'wsl:<distro>' | 'ssh:<profileId>'`。distro 编码进 id，不再有 `windowsStorageBackend`/`wslDistro` 字段，也不再解析 claude 路径。
- `targets.json` 退为 **target 目录**（`{schemaVersion, targets}`），删 `defaultTargetId`/`wslDistro`/`migrateIfNeeded`；`listTargets` 的 ssh 对账（从 `ssh_profiles/` live 派生）保留。
- **bootstrap 次序**：读本地 `homeTargetId`（平台默认：桌面 `local`、Android 首个 ssh）→ 解出 home `RuntimeTarget` → 装 home 上下文（见 §4）→ 读 targets.json 目录。删 `currentLegacyTargetId`/`synthTarget`/`wslDistroFromPrefs`/legacy install 块。
- **删旧旋钮**：`SessionPreferences.connectionMode`/`windowsStorageBackend` 字段 + cubit setter 删除；`ConnectionModeService` 仅留 `isSshMode`（由 home target kind 推导）；`ConnectionMode`/`WindowsStorageBackend` enum 按审计存废（若仅内部传输用途则降为内部描述符，否则删）。
- **UI**：平台域定 home target 选择器（桌面非 Win=只读 `local`；Win∈{`local`,`wsl:<distro>`}；Android∈{`ssh:<profile>`…}），就地 `/config/session` 替换后端开关；Android quick-switch 改 home 切换；SSH profiles 页降纯管理；删死的连接模式开关（`kShowConnectionModeSetting`）。

## 3. 清除兼容脚手架（P1 顺带，回到最优终态）

- **预备阶段**：`folders` 成为**唯一磁盘形状**——删 `foldersFromLegacyJson` 读旧分支（改严格 `foldersFromJson(json['folders'])`）、删 Workspace/AppSession `toJson` 的 `primaryPath`/`additionalPaths` 双写、删任何 `@Deprecated` 旧 getter 与 schemaVersion 兼容读旧。保留 `firstFolderPath`/`extraFolderPaths`/`folderPaths`。
- **P0**：删 `RuntimeTargetRegistry.migrateIfNeeded`/`defaultTarget`/`setDefaultTargetId`/`wslDistro`、app_shell 的 `currentLegacyTargetId`/`synthTarget`、SessionPreferences 旧旋钮双写/映射。

## 4. P2：去单例 —— `RuntimeContext` + `RuntimeContextRegistry`

把全局单例 `RuntimeStorageContext._current`（45 处 `RuntimeStorageContext.current` 读、17 文件）替换为**可实例化上下文 + 按 target 缓存的注册表**。

### 4.1 `RuntimeContext`（今天 `RuntimeStorageContext` 的实例形态）

```dart
// lib/services/storage/runtime_context.dart
class RuntimeContext {
  RuntimeContext({
    required this.target,
    required this.filesystem,
    required this.home,
    required this.cwd,
    required this.appDataRoot,
    required this.paths,
  });
  final RuntimeTarget target;
  final Filesystem filesystem;
  final String home, cwd, appDataRoot;
  final AppPaths paths;
  bool get usesPosixPaths => target.kind != RuntimeKind.local || /* wsl/ssh */ ...;
  // 派生布局（即今天 StorageRootsSnapshot 的内容，并入此处）：
  late final WorkspaceLayout workspace = WorkspaceLayout(teampilotRoot: appDataRoot, fs: filesystem);
  late final RuntimeLayout layout = RuntimeLayout(teampilotRoot: appDataRoot, fs: filesystem, workspace: workspace);
  bool get storageIsRemote => filesystem is SftpFilesystem;
}
```

- 传输（PTY/SSH）**不**并入 `RuntimeContext` 字段（本期仍由 shell 工厂按 `target.kind` 现造，P0/P1 已归一）；`RuntimeContext` 聚焦 fs + 布局 + 路径。`StorageRootsSnapshot` 的全部派生路径**并入** `RuntimeContext`，`StorageRoots` 退役（见 §6）。

### 4.2 `RuntimeContextResolver`（平台物化，提取自旧 `resolve()`）

把 `RuntimeStorageContext.resolve()`/`_resolveNative/_resolveWsl/_resolveSsh` 的平台分支**原样迁出**为 `RuntimeContextResolver.resolve(RuntimeTarget target, {deps})`——入参从"分散 prefs/旗标"变成**具体 `RuntimeTarget`**，逻辑不变。删除旧 `RuntimeStorageContext` 类与其静态 `_current`/`current`/`install`/`installForTarget`。

### 4.3 `RuntimeContextRegistry`

```dart
// lib/services/storage/runtime_context_registry.dart
class RuntimeContextRegistry {
  RuntimeContextRegistry({required RuntimeContextResolver resolver, required RuntimeTarget homeTarget, required <deps>});
  RuntimeContext home();                                  // 控制面（homeTargetId）— bootstrap 后常驻
  Future<RuntimeContext> forTarget(RuntimeTarget target); // 工作面，按需物化 + 缓存（按 target.id）
  Future<void> dispose(String targetId);                  // 远程断开/工作区关闭回收（含 SSHClient）
  Future<void> rebindHome(RuntimeTarget homeTarget);      // 用户改 home 时重建控制面
}
```

- `home()` 在 bootstrap 物化一次并缓存；`forTarget` 惰性物化、按 `target.id` 缓存；同一台机的多个工作区/会话**复用** `SSHClient`（注册表持有）。
- 删除全局 `RuntimeStorageContext.current`。所有读点改为：**控制面 → `registry.home()`；工作面 → `registry.forTarget(folderTarget)`**（§5 分类）。

## 5. 控制面 / 工作面拆分

| 面 | 内容 | 上下文来源 |
|---|---|---|
| **控制面** | `teams/`、workspace manifests、`targets.json`、`ssh_profiles/`、`ui/`、`cli-defaults/`（权威）、项目列表 | **永远 `registry.home()`** |
| **工作面** | 工作区工作目录、`sessions/{id}/runtime/`、CLI 执行、provisioning（按 launch 惰性物化） | **`registry.forTarget(folderTarget)`** |

- `AppStorage.fs/cwd/paths` 静态门面**保留**，改为转发 `registry.home()`（控制面），覆盖现有数百处控制面读点零改动（doc §10.2）。新增 bootstrap `AppStorage.bind(registry)`。
- **工作面消费方显式取上下文**（不走 `AppStorage`）：`SessionLifecycleService`/`session_launch_service`/provisioning/CLI 定位与执行——传入或解析出 `RuntimeContext`（见 §7）。
- **45 处 `RuntimeStorageContext.current` 审计**（17 文件）：逐点判定控制面 vs 工作面并改写：
  - 控制面（manifests、teams、ui、cli-defaults、provider catalog 读）→ `AppStorage.*`（已转发 home）或 `registry.home()`。
  - 工作面（会话运行时、CLI 执行、host 执行环境、extension detector 对工作机的探测、git installer、cli locator/validator/installer、member config 物化、opencode/config-profile 物化）→ 该会话/工作区解析出的 `RuntimeContext`。
  - 文件清单（待逐一分类）：`extension_detector`、`workspace_dnd/path_namespace`、`host/host_execution_environment`、`provider/config_profile_infrastructure`、`session/session_lifecycle_service`、`cli/git_installer`、`cli/cli_tool_locator`、`cli/cli_executable_validator`、`cli/cli_installer_service`、`cli/member_config/member_config_inspector`、`cli/registry/config_profile/opencode_config_profile_capability`、`cubits/chat/session_launch_service`、`app/app_shell`、`pages/home_workspace/workspace/worktree_group_section`、`pages/home_workspace/workspace/member_detail_dialog`。

### 5.1 远程离线 → 项目列表仍可读

项目列表/工作区 manifest 属控制面 = `registry.home()`（桌面恒 local）。某工作区的远程 target 离线时，`forTarget(offlineSsh)` 仅在**启动该工作区会话**时失败；`home()` 读 manifest 列表不受影响 → 项目列表照常可见（§12 P2 验收点）。

## 6. 单例迁移清单落地（doc §10）

1. `RuntimeStorageContext` 静态单例 → `RuntimeContext` 实例 + `RuntimeContextRegistry` + `RuntimeContextResolver`。**删** `_current`/`current`/`install`/`installForTarget`。
2. `AppStorage.fs/cwd/paths` → 转发 `registry.home()`；新增 `AppStorage.bind(registry)`。
3. `WorkspaceLayout`/`RuntimeLayout`：已 `(teampilotRoot, fs)` 参数化 → 按解析出的 context 各构造一个（其 root + 其 fs），**不再**全局 `AppStorage.fs`。
4. `StorageRoots`/`StorageRootsSnapshot` **退役**：其派生路径并入 `RuntimeContext`；现有 `StorageRoots.resolve()` 消费方改取 `registry.home()`（控制面）或显式 context（工作面）。
5. `app_shell` 的 `install/reinstall/reloadRemoteBackedAppData` → 装配 `home + registry`，而非切换全局后端；改 home 走 `registry.rebindHome` + reload。
6. 审计所有 `RuntimeStorageContext.current` 读点（§5），分清控制面/工作面。
7. **堵裸 `dart:io`**：`runtime_layout.dart:338` `Directory(path).list(followLinks:true)`、`:363` `Directory(target).resolveSymbolicLinks()` → 改走 `Filesystem` 接口（必要时给 `Filesystem` 补 `listDir`/`resolveSymlink`），否则远程 context 一用即崩。
8. **补 `SftpFilesystem.readSymlinkTarget`**（当前恒 `null`，line 86）：经 `store.readlink`/dartssh2 实现，恢复 `ResourceMaterializer` 物化幂等（否则远程每次 launch 重链/重拷）。

## 7. 每目录 target 多机解析（启动一个会话）

```
openSessionTab / launch
  → workCtx = registry.forTarget(workspace 的 target)      // §4.3；P2: 整工作区一个 target
        local : LocalFilesystem (+ 本地 PTY)
        wsl   : WslFilesystem(distro) (+ wsl exec)
        ssh   : 复用/新建 SSHClient → SftpFilesystem (+ SshPty)
  → 工作目录 / sessions/{id}/runtime/ / provisioning 全部在 workCtx
  → 会话元数据（manifest、members[]）仍写 registry.home()（控制面）
  → TerminalSession.connect(transport 由 target.kind 现造)
```

- `SessionLifecycleService.prepareLaunch`：`workDir` 与运行时树由 `workCtx` 解析（取代今天的全局 `AppStorage`）；继承物化（`cli-defaults`/workspace config）按 launch 惰性铺到 workCtx 的机内（§5.2 推广属 P3 mixed；**P2 项目远程下整工作区同机，继承 symlink 自然在该机根内闭合**）。
- `Workspace.folders[].targetId`：P2 工作区所有 folder 同 target（项目远程）；UI 设/改工作区 target（落 folder.targetId）。mixed/per-member = P3。

## 8. 关键文件（P2 增量）

| 文件 | 动作 |
|------|------|
| `lib/services/storage/runtime_context.dart` | 新增 `RuntimeContext`（含派生 layout/paths） |
| `lib/services/storage/runtime_context_resolver.dart` | 新增（迁出旧 resolve 平台分支） |
| `lib/services/storage/runtime_context_registry.dart` | 新增（home/forTarget/dispose/rebindHome + SSHClient 缓存） |
| `lib/services/storage/runtime_storage_context.dart` | **删除**（功能拆入上三者） |
| `lib/services/storage/storage_resolver.dart` | `StorageRoots`/`StorageRootsSnapshot` 退役，派生并入 RuntimeContext |
| `lib/services/storage/app_storage.dart` | `fs/cwd/paths` 转发 `registry.home()`；新增 `bind(registry)` |
| `lib/services/storage/runtime_layout.dart` | 堵 :338/:363 裸 dart:io，走 Filesystem |
| `lib/services/io/filesystem.dart` | 视需要补 `listDir`/`resolveSymlink` 抽象 |
| `lib/services/io/sftp_filesystem.dart` | 实现 `readSymlinkTarget` |
| `lib/services/session/session_lifecycle_service.dart`、`cubits/chat/session_launch_service.dart` | 工作面取 `registry.forTarget`；元数据走 home |
| `lib/app/app_shell.dart` | 装配 registry（home + resolver）；`AppStorage.bind`；改 home 走 rebindHome |
| 工作区 target UI（`/config` 或工作区设置） | 设/改工作区 target → folder.targetId |
| §5 列出的 ~15 个 `RuntimeStorageContext.current` 消费文件 | 按控制面/工作面改写 |

## 9. 测试策略

**P1**（同 standalone P1 稿 §7）：HomeTargetStore；home target 解析；bootstrap 次序（homeTargetId→home context 等价旧选择）；targets.json 终态；ConnectionModeService.isSshMode；UI 选择器平台域定；清脚手架 grep 守卫。

**P2**：
1. `RuntimeContextResolver` 单测：每 kind 物化的 context（mode/appDataRoot/usesPosixPaths）等价旧 `resolve()`（金标准）。
2. `RuntimeContextRegistry` 单测：`home()` 稳定；`forTarget` 惰性物化 + 缓存命中（同 target 复用同 context/SSHClient）；`dispose` 回收；`rebindHome` 重建。
3. **两工作区互不影响**：注册表同时持 home(local) 与 forTarget(ssh)，对各自 fs 读写互不串扰（mock 两个 fs，断言隔离）。
4. **远程离线项目列表可读**：`forTarget(ssh)` 抛错（mock 连接失败）时，`home()` 读 workspace 列表仍成功。
5. `AppStorage.fs/paths/cwd` 转发 `registry.home()`（绑定后断言指向 home context）。
6. `runtime_layout` 经 Filesystem（注入 in-memory fs）跑通 :338/:363 等价逻辑，无 `dart:io`。
7. `SftpFilesystem.readSymlinkTarget` 单测（mock store.readlink 返回目标）。
8. 会话启动：`prepareLaunch` 用 `forTarget(workspace target)` 的 workDir/runtime 树；元数据写 home。
9. **45 处审计回归**：全仓 `grep RuntimeStorageContext.current` → 0（除已删类）；每改写点有对应控制面/工作面测试或既有测试覆盖。
10. 全量：`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
11. 手验金路径：桌面 local 启动；Android(home=ssh) 等价；工作区 A(local)+B(ssh) 并存；拔远程机 → 项目列表仍可见、仅 B 会话启动失败。

## 10. 不在 P1+P2 范围（YAGNI / P3+）

- 成员远程：`AppSession.folderAssignments`、mixed 工作区 per-member 解析、反向隧道、bus raw-socket/per-session token、远程 relay 物化、跨机产物 MCP（P3）。
- `remoteOs` 探测与 Windows-remote 分支（symlink→copy、relay windows 二进制）（P3）。
- 继承 ancestry 跨机物化到工作机（§5.2 的 P3 推广；P2 项目远程同机时自然闭合，无需跨机物化）。
- 凭证物化到远程 `providers/`（§5.1，P3）。
- per-target 连接弹性/自动重连/会话 resume（P4）。
- distro 发现 UI、远程目录浏览器（后续）。
