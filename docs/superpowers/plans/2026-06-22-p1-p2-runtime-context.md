# P1+P2 — home target 归一 + 去单例 + 控制面/工作面拆分 + 每目录 target（最优终态，零兼容）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** P1 确立 home target 唯一作用域层 + 权威源反转到设备本地 `homeTargetId` + 选 target UI；P2 去存储单例（`RuntimeContext` + `RuntimeContextRegistry`）、拆控制面/工作面、`Workspace.folders[].targetId` 多机解析（**解锁项目远程**：两工作区分落 local/ssh 互不影响、远程离线项目列表仍可读）。全程零兼容、最优终态。

**Architecture:** 设备本地 `HomeTargetStore` 为 home 唯一权威；`targets.json` 退为 target 目录。去单例：`RuntimeStorageContext._current` → `RuntimeContext`(实例) + `RuntimeContextResolver`(平台物化) + `RuntimeContextRegistry`(home()/forTarget()/dispose()，缓存 SSHClient)。`AppStorage.fs/cwd/paths` 转发 `registry.home()`（控制面，零改现有读点）；工作面消费方显式取 `forTarget(folderTarget)`。会话启动按工作区 folder 的 targetId 解析工作面上下文，元数据仍走 home。清除前序全部兼容脚手架。

**Tech Stack:** Dart / Flutter，`flutter_bloc`，`shared_preferences`，`dartssh2`(SftpClient.readlink)，`package:flutter_test`。

**Branch:** 建立在 `feat/p0-runtime-target` 之上——切 `feat/p1-p2-runtime-context`。

## Global Constraints

- **零兼容、最优终态**：不读旧字段、不双写、不留 schemaVersion 兼容、不做读旧迁移。旧磁盘 manifest/prefs 失效是用户接受的已知后果。
- **home 身份 bootstrap-local**：`homeTargetId` 存设备本地 SharedPrefs（唯一 home 权威）；`targets.json` 是 home 上的 target 目录（list+label）。（team-lead 已确认采纳。）
- **P2 不含 P3**：无反向隧道/成员远程/`folderAssignments`/跨机产物/远程 relay/`remoteOs` 探测/Windows-remote 分支。成员仍全在 home；`folders[].targetId` 多机解析做出来即可，跨机协调留 P3。`RuntimeContextResolver` 仅复刻今天 local/wsl/ssh 三 kind 的物化。
- 设计权威：[docs/superpowers/specs/2026-06-22-p1-p2-runtime-context-design.md](../specs/2026-06-22-p1-p2-runtime-context-design.md)。
- 完成判据（每任务 + 总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
- l10n 删除字符串走 `app_en.arb`/`app_zh.arb` + `flutter pub get`，再 `dart run tool/gen_warmup_glyphs.dart`。
- 频繁提交：每任务 ≥1 commit。

## 编排总览

- **Phase A（P1，Task 1–8）**：按 [docs/superpowers/plans/2026-06-22-p1-home-target.md](2026-06-22-p1-home-target.md) **逐字执行其 Task 1–8**（本合并计划据此 incorporated by reference；步骤级代码以该文件为准）。交付：home 权威反转、选 target UI、清除预备+P0 脚手架。Phase A 结束须 analyze+test 全绿。
- **Phase B（P2，Task 9–18，本文件全详）**：去单例 + 控制面/工作面拆分 + 每目录 target。
- **顺序铁律**：先建抽象与新上下文 → AppStorage 转发 + 临时委派桥（保编译绿）→ 分批迁移 45 处读点 → 会话工作面解析 → 删旧单例与桥。**临时委派桥是同一 PR 内的重构排序手段（最终任务删除），非向后兼容**。

---

## Phase A — P1（Task 1–8，incorporated by reference）

- [ ] **Task 1–8**：执行 `2026-06-22-p1-home-target.md` 的 Task 1–8（HomeTargetStore → targets.json 终态 → app_shell 反转+bootstrap → 删 prefs 旧旋钮+ConnectionModeService → home target 选择器 UI → Android 首启门+bootstrap 回归 → 清预备脚手架 → 终态 grep 守卫）。**Gate**：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿后方进 Phase B。

> 注：Phase A 的 Task 3 已让 `defaultTargetResolver()` 返回由 `homeTargetId` 解析的 home target；Phase B 将以此 home target 装配 registry。

---

## Phase B — P2

### Task 9: 堵 `dart:io` 漏洞 + `SftpFilesystem.readSymlinkTarget`（远程 context 前置）

**Files:**
- Modify: `client/lib/services/io/filesystem.dart` (补抽象，若缺)
- Modify: `client/lib/services/io/sftp_filesystem.dart` (实现 readSymlinkTarget)
- Modify: `client/lib/services/io/local_filesystem.dart`, `client/lib/services/io/wsl_filesystem.dart` (实现新抽象)
- Modify: `client/lib/services/storage/runtime_layout.dart` (:338/:363 改走 fs)
- Test: `client/test/services/io/sftp_readlink_test.dart`, `client/test/services/storage/runtime_layout_fs_test.dart`

**Interfaces:**
- Produces: `Filesystem.listDir(String path, {bool followLinks})` 与 `Filesystem.resolveSymlink(String path)`（如不存在则新增）；`SftpFilesystem.readSymlinkTarget` 返回真实目标。

- [ ] **Step 1: 审计 Filesystem 现有能力**

```bash
cd client && grep -n "listDir\|resolveSymlink\|readSymlinkTarget\|abstract class Filesystem\|Future" lib/services/io/filesystem.dart
```
确认 `listDir`/`resolveSymlink` 是否已有；runtime_layout :338/:363 当前直接用 `dart:io Directory`。

- [ ] **Step 2: 写失败测试**（readSymlinkTarget + runtime_layout 经 fs）

```dart
// client/test/services/io/sftp_readlink_test.dart — mock RemoteFileStore.readlink 返回 '/target'
// 断言 SftpFilesystem(store).readSymlinkTarget('/link') == '/target'
// client/test/services/storage/runtime_layout_fs_test.dart — 注入 in-memory Filesystem，
// 断言原 :338（探测目录可列）/ :363（解析符号链接目标）逻辑经 fs 接口跑通、无 dart:io。
```

- [ ] **Step 3: 运行 → 失败**

Run: `cd client && flutter test test/services/io/sftp_readlink_test.dart test/services/storage/runtime_layout_fs_test.dart`
Expected: FAIL（readSymlinkTarget 恒 null / runtime_layout 仍用 dart:io）。

- [ ] **Step 4: 实现**
  - `SftpFilesystem.readSymlinkTarget`（替换 line 86 的 `=> null`）：
    ```dart
    Future<String?> readSymlinkTarget(String linkPath) async => store.readlink(linkPath);
    ```
    （`RemoteFileStore.readlink` 经 dartssh2 `SftpClient.readlink`/`link`；若 store 无 readlink，补一个薄方法。）
  - `Filesystem` 补 `listDir`/`resolveSymlink`（若缺），各 fs 实现：Local/Wsl 用 `dart:io`（本地实现内允许），Sftp 用 store。
  - `runtime_layout.dart` :338 `Directory(path).list(followLinks:true).take(1).drain()` → `fs.listDir(path, followLinks:true)`；:363 `Directory(target).resolveSymbolicLinks()` → `fs.resolveSymlink(target)`。删 `import 'dart:io'`（若再无用）。

- [ ] **Step 5: 运行 → 通过 + 既有 layout 测试**

Run: `cd client && flutter test test/services/io test/services/storage/runtime_layout_fs_test.dart test/services/storage/`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/io client/lib/services/storage/runtime_layout.dart client/test/services/io client/test/services/storage/runtime_layout_fs_test.dart
git commit -m "feat: route runtime_layout through Filesystem; implement SftpFilesystem.readSymlinkTarget"
```

---

### Task 10: `RuntimeContext` + `RuntimeContextResolver`（实例化形态）

**Files:**
- Create: `client/lib/services/storage/runtime_context.dart`
- Create: `client/lib/services/storage/runtime_context_resolver.dart`
- Test: `client/test/services/storage/runtime_context_resolver_test.dart`

**Interfaces:**
- Consumes: `RuntimeTarget`, `Filesystem`, `WorkspaceLayout`/`RuntimeLayout`, 旧 `RuntimeStorageContext._resolve*` 逻辑（迁出）。
- Produces:
  - `class RuntimeContext { final RuntimeTarget target; final Filesystem filesystem; final String home, cwd, appDataRoot; final AppPaths paths; bool get usesPosixPaths; WorkspaceLayout get workspace; RuntimeLayout get layout; bool get storageIsRemote; }` （并入旧 `StorageRootsSnapshot` 的派生路径 getter）
  - `class RuntimeContextResolver { RuntimeContextResolver({SshClientFactory?, RemoteSshStoragePathResolver?, required String nativeAppDataPath, String? nativeHome, String? nativeCwd}); Future<RuntimeContext> resolve(RuntimeTarget target, {SshProfile? sshProfile}); }`

- [ ] **Step 1: 写金标准等价测试**（resolve(target) ≡ 旧 RuntimeStorageContext.resolve）

```dart
// 对 local / wsl(Ubuntu) / ssh(profile)：
// RuntimeContextResolver(...).resolve(RuntimeTarget.local()) 的 (appDataRoot, usesPosixPaths, fs 类型)
// 等价旧 RuntimeStorageContext.resolve(isSshMode:false, nativeAppDataPath:...).
// 复用 P0 install_for_target_test 的 mock SSH/WSL plumbing。
```

- [ ] **Step 2: 运行 → 失败**

Run: `cd client && flutter test test/services/storage/runtime_context_resolver_test.dart`
Expected: FAIL — 新类不存在。

- [ ] **Step 3: 实现**
  - `RuntimeContext`：见 Interfaces；`workspace`/`layout` 用 `late final` 由 `appDataRoot`+`filesystem` 构造；`usesPosixPaths` 由 `target.kind != local`（wsl/ssh = posix）。
  - `RuntimeContextResolver.resolve`：把旧 `RuntimeStorageContext.resolve()/_resolveNative/_resolveWsl/_resolveSsh` 的 body **原样搬入**，入参由分散 prefs/旗标换成 `RuntimeTarget`（`target.kind`→分支，`target.wslDistro`→distro，`sshProfile`→ssh 分支）。产出 `RuntimeContext`（而非旧单例实例）。**不**碰 `RuntimeStorageContext`（本任务并存；删除在 Task 18）。

- [ ] **Step 4: 运行 → 通过**

Run: `cd client && flutter test test/services/storage/runtime_context_resolver_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_context.dart client/lib/services/storage/runtime_context_resolver.dart client/test/services/storage/runtime_context_resolver_test.dart
git commit -m "feat: add RuntimeContext + RuntimeContextResolver (instance form of resolve)"
```

---

### Task 11: `RuntimeContextRegistry`（home/forTarget/dispose/rebindHome）

**Files:**
- Create: `client/lib/services/storage/runtime_context_registry.dart`
- Test: `client/test/services/storage/runtime_context_registry_test.dart`

**Interfaces:**
- Consumes: `RuntimeContextResolver` (Task 10), `RuntimeTarget`.
- Produces: `class RuntimeContextRegistry { RuntimeContextRegistry({required RuntimeContextResolver resolver, required RuntimeTarget homeTarget, SshProfile? Function(String id)? sshProfileById}); RuntimeContext home(); Future<RuntimeContext> forTarget(RuntimeTarget target); Future<void> dispose(String targetId); Future<void> rebindHome(RuntimeTarget homeTarget); Future<void> ensureHome(); }`

- [ ] **Step 1: 写失败测试**（缓存 / 隔离 / 离线可读 / dispose / rebind）

```dart
test('home() returns the bootstrapped home context', ...);
test('forTarget caches by target id (same context instance on second call)', ...);
test('two targets resolve to independent contexts (isolation)', () async {
  // homeTarget=local, forTarget(ssh) -> different fs; writing via one does not affect the other (mock fs)
});
test('forTarget(ssh) failure does not break home() reads (offline project list)', () async {
  // resolver throws for ssh; home() still returns the local context
});
test('dispose evicts cached context (and closes ssh client)', ...);
test('rebindHome swaps the home context', ...);
```

- [ ] **Step 2: 运行 → 失败**

Run: `cd client && flutter test test/services/storage/runtime_context_registry_test.dart`
Expected: FAIL。

- [ ] **Step 3: 实现**

```dart
class RuntimeContextRegistry {
  RuntimeContextRegistry({required RuntimeContextResolver resolver, required RuntimeTarget homeTarget, SshProfile? Function(String)? sshProfileById})
    : _resolver = resolver, _homeTarget = homeTarget, _sshProfileById = sshProfileById;
  final RuntimeContextResolver _resolver;
  RuntimeTarget _homeTarget;
  final SshProfile? Function(String)? _sshProfileById;
  final _cache = <String, RuntimeContext>{};
  RuntimeContext? _home;

  Future<void> ensureHome() async { _home ??= await forTarget(_homeTarget); }
  RuntimeContext home() => _home ?? (throw StateError('home context not initialised; call ensureHome()'));

  Future<RuntimeContext> forTarget(RuntimeTarget target) async {
    final cached = _cache[target.id];
    if (cached != null) return cached;
    final ctx = await _resolver.resolve(target,
        sshProfile: target.sshProfileId != null ? _sshProfileById?.call(target.sshProfileId!) : null);
    _cache[target.id] = ctx;
    return ctx;
  }

  Future<void> dispose(String targetId) async {
    final ctx = _cache.remove(targetId);
    if (ctx?.filesystem is SftpFilesystem) { /* close ssh client via store */ }
    if (identical(_home, ctx)) _home = null;
  }

  Future<void> rebindHome(RuntimeTarget homeTarget) async {
    _homeTarget = homeTarget;
    _home = await forTarget(homeTarget); // forTarget caches; rebind picks/creates its context
  }
}
```
（`ensureHome` 在 bootstrap 调一次；`home()` 同步返回缓存。SSHClient 关闭经 store/clientFactory，按现有 `disconnectProfile` 接口接。）

- [ ] **Step 4: 运行 → 通过**

Run: `cd client && flutter test test/services/storage/runtime_context_registry_test.dart`
Expected: PASS（含隔离 + 离线可读两条核心验收）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_context_registry.dart client/test/services/storage/runtime_context_registry_test.dart
git commit -m "feat: add RuntimeContextRegistry (home/forTarget/dispose/rebindHome, ssh reuse)"
```

---

### Task 12: `AppStorage` 转发 registry.home() + app_shell 装配 + 临时委派桥

**Files:**
- Modify: `client/lib/services/storage/app_storage.dart` (fs/cwd/paths → registry.home()；新增 bind)
- Modify: `client/lib/app/app_shell.dart` (装配 registry；ensureHome；AppStorage.bind；改 home 走 rebindHome)
- Modify: `client/lib/services/storage/runtime_storage_context.dart` (临时：`current` 委派 registry.home()——Task 18 删)

**Interfaces:**
- Produces: `static void AppStorage.bind(RuntimeContextRegistry registry)`；`AppStorage.fs => _registry.home().filesystem`、`paths => _registry.home().paths`、`cwd => _registry.home().cwd`。

- [ ] **Step 1: AppStorage 转发**

```dart
class AppStorage {
  static RuntimeContextRegistry? _registry;
  static void bind(RuntimeContextRegistry registry) => _registry = registry;
  static Filesystem get fs => _registry!.home().filesystem;
  static AppPaths get paths => _registry!.home().paths;
  static String get cwd => _registry!.home().cwd;
  // 保留 syncPaths/setCurrentForTesting 等测试钩子，改为基于注入的 home context
}
```

- [ ] **Step 2: app_shell 装配** — 替换 `RuntimeStorageContext.install/installForTarget` bootstrap：

```dart
  final resolver = RuntimeContextResolver(
    sshClientFactory: sshClientFactory,
    nativeAppDataPath: nativeAppDataPath,
    nativeHome: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
    nativeCwd: defaultWorkspaceDirectory,
  );
  final runtimeContextRegistry = RuntimeContextRegistry(
    resolver: resolver,
    homeTarget: defaultTargetResolver(), // Phase A: home target from homeTargetId
    sshProfileById: (id) => sshProfileCubit.state.profiles.where((p) => p.id == id).firstOrNull,
  );
  await runtimeContextRegistry.ensureHome();
  AppStorage.bind(runtimeContextRegistry);
```
改 home（用户在选择器选 home）：`setHomeTarget(id)` → `runtimeContextRegistry.rebindHome(homeTargetFromId(id))` → `reloadRemoteBackedAppData(...)`。删 `reinstallStorageContext`/`installForTarget` 路径（home 切换走 rebindHome）。

- [ ] **Step 3: 临时委派桥**（保其余 15 文件编译绿，Task 18 删）— 在 `runtime_storage_context.dart` 暂留一个**只读委派**：
```dart
// TRANSIENT MIGRATION BRIDGE — removed in Task 18. Not backward-compat:
// lets the not-yet-migrated current-readers compile while we reroute them.
class RuntimeStorageContext {
  static RuntimeContextRegistry? _registry;
  static void bindForMigration(RuntimeContextRegistry r) => _registry = r;
  static RuntimeContext get current => _registry!.home();
}
```
app_shell 调 `RuntimeStorageContext.bindForMigration(runtimeContextRegistry)`。删除旧 `_resolve*`/`install`/`installForTarget`/`_current`（逻辑已迁 Task 10）。

- [ ] **Step 4: StorageRoots → home()** — `storage_resolver.dart`：`_resolveUncached` 改 `return registry.home()`（或直接让消费方取 `registry.home()`；StorageRoots 完整退役在 Task 16）。本步先让其编译并指向 home。

- [ ] **Step 5: Analyze + 全量**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS（委派桥使 15 个 current-reader 仍绿；行为 = 全部读 home，等价桌面今天）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/storage/app_storage.dart client/lib/app/app_shell.dart client/lib/services/storage/runtime_storage_context.dart client/lib/services/storage/storage_resolver.dart
git commit -m "refactor: AppStorage forwards registry.home(); assemble registry (transient bridge)"
```

---

### Task 13: 迁移控制面读点（current → AppStorage/home）

**Files (modify):** 控制面归属的 current-reader（读 teams/manifests/ui/cli-defaults/provider catalog）：
- `client/lib/services/provider/config_profile_infrastructure.dart`
- `client/lib/services/cli/registry/config_profile/opencode_config_profile_capability.dart`
- `client/lib/services/cli/member_config/member_config_inspector.dart`
- `client/lib/pages/home_workspace/workspace/worktree_group_section.dart`
- `client/lib/pages/home_workspace/workspace/member_detail_dialog.dart`
- `client/lib/services/workspace_dnd/path_namespace.dart`（判定：UI 路径命名空间→控制面）

**Interfaces:** Consumes `AppStorage.*`（已转发 home）。

- [ ] **Step 1: 逐文件** 把 `RuntimeStorageContext.current.<x>` 改为 `AppStorage.<x>`（`.filesystem`→`AppStorage.fs`、`.paths`→`AppStorage.paths`、`.cwd`→`AppStorage.cwd`、`.appDataRoot`→`AppStorage.paths.basePath`）。这些点确为控制面（home），语义不变。

- [ ] **Step 2: Analyze + 相关测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/provider lib/services/cli lib/pages/home_workspace lib/services/workspace_dnd && flutter test --exclude-tags integration`
Expected: CLEAN + PASS。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: route control-plane readers through AppStorage(home)"
```

---

### Task 14: 迁移工作面读点（current → registry.forTarget）— host/CLI 执行与探测

**Files (modify):** 工作面归属（对工作机执行/探测）：
- `client/lib/services/host/host_execution_environment.dart`
- `client/lib/services/extension/extension_detector.dart`
- `client/lib/services/cli/cli_tool_locator.dart`
- `client/lib/services/cli/cli_executable_validator.dart`
- `client/lib/services/cli/cli_installer_service.dart`
- `client/lib/services/cli/git_installer.dart`

**Interfaces:** Consumes `RuntimeContextRegistry.forTarget` / 传入的 `RuntimeContext`。本任务这些服务多由**会话/工作区**驱动，接收 `RuntimeContext` 参数（由调用方 Task 17 传入工作面 ctx）。P2 阶段若某服务暂只在 home 跑（成员全在 home），可先接 `registry.home()` 的 context，但**签名改为接收 `RuntimeContext`**，为 Task 17 的 forTarget 注入就位。

- [ ] **Step 1: 给每个服务加 `RuntimeContext` 入参**（构造或方法），内部 `ctx.filesystem`/`ctx.layout`/`ctx.paths` 取代 `RuntimeStorageContext.current`。调用方暂传 `registry.home()`（Task 17 改 forTarget）。

- [ ] **Step 2: Analyze + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/host lib/services/extension lib/services/cli && flutter test --exclude-tags integration`
Expected: CLEAN + PASS。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: thread RuntimeContext into host/CLI work-plane services"
```

---

### Task 15: 迁移会话生命周期读点（session_lifecycle_service / session_launch_service）

**Files (modify):**
- `client/lib/services/session/session_lifecycle_service.dart`
- `client/lib/cubits/chat/session_launch_service.dart`

**Interfaces:** Consumes `RuntimeContextRegistry`。

- [ ] **Step 1:** 把这两处 `RuntimeStorageContext.current` 改为：控制面读（会话元数据/manifest）→ `registry.home()`；工作面（runtime 树/工作目录/provisioning 调用）→ `registry.forTarget(<工作区 target>)`（Task 17 提供 target 解析；本步先 `home()` 占位并标注 TODO 接 forTarget）。保持行为 = home（桌面等价）。

- [ ] **Step 2: Analyze + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/session lib/cubits/chat && flutter test --exclude-tags integration`
Expected: CLEAN + PASS。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: route session lifecycle reads through registry"
```

---

### Task 16: `StorageRoots`/`StorageRootsSnapshot` 退役

**Files:**
- Modify/Delete: `client/lib/services/storage/storage_resolver.dart`
- Modify: 其消费方（`grep -rln StorageRoots lib`）

**Interfaces:** 消费方改取 `registry.home()`（控制面）或显式 `RuntimeContext`（工作面）。

- [ ] **Step 1:** `grep -rln "StorageRoots\b" lib`；逐消费方替换：`storageRoots.resolve()` 的 snapshot 字段（`fs/layout/workspace/launchProfilesDir/...`）→ 等价取 `registry.home().<...>` 或 `RuntimeContext` 的派生 getter（Task 10 已并入这些路径）。删 `StorageRoots`/`StorageRootsSnapshot` 类与 `app_shell` 里的 `storageRoots` 装配/`invalidate`/`reinstallAndResolve`（home 切换走 `rebindHome`）。

- [ ] **Step 2: Analyze + 全量**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS。

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: retire StorageRoots; derived paths live on RuntimeContext"
```

---

### Task 17: 每目录 target 多机解析（会话工作面 = forTarget(workspace target)）

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`, `client/lib/cubits/chat/session_launch_service.dart`
- Modify: 工作区 target 设置 UI（`/config` 或工作区设置面板）+ 写 `Workspace.folders[].targetId`
- Test: `client/test/services/session/session_work_plane_test.dart`

**Interfaces:** Consumes `Workspace.folders[].targetId`, `RuntimeContextRegistry.forTarget`, `listTargets`.

- [ ] **Step 1: 解析工作面 target** — 在会话启动路径加：
```dart
RuntimeTarget workspaceTarget(Workspace ws) {
  final id = ws.folders.isEmpty ? RuntimeTarget.localId : ws.folders.first.targetId; // P2: 整工作区一个 target
  return /* 由 id 解析为 RuntimeTarget：local/wsl/ssh，ssh 经 sshProfileById */;
}
// 工作面 ctx：
final workCtx = await registry.forTarget(workspaceTarget(ws));
```
把 Task 14/15 占位的 `registry.home()`（工作面那部分）改为 `workCtx`：工作目录、`sessions/{id}/runtime/`、provisioning、CLI 定位/执行用 `workCtx`；会话元数据/manifest 仍 `registry.home()`。

- [ ] **Step 2: 工作区 target UI** — 在工作区设置加"选 target"（来自 `registry.listTargets()`），选中写 `repo.updateWorkspaceFolders(...)`（给所有 folder 设同一 `targetId`）。新增仓库写 API `updateWorkspaceFolders(workspaceId, List<WorkspaceFolder>)`（替代 P2 前的 string API；本期最优形态）。

- [ ] **Step 3: 写测试**

```dart
test('session on a local workspace uses home/local work context', ...);
test('session on an ssh workspace uses forTarget(ssh) work context; metadata still on home', () async {
  // workspace.folders.first.targetId = 'ssh:p1'
  // assert prepareLaunch resolves work fs == ssh ctx fs; manifest write goes to home fs
});
test('two workspaces (local + ssh) launch into independent contexts', ...);
```

- [ ] **Step 4: 运行 → 通过**

Run: `cd client && flutter test test/services/session/session_work_plane_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + CLEAN。

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: resolve session work-plane context from workspace folder targetId"
```

---

### Task 18: 删除单例 + 委派桥 + 终态回归

**Files:**
- Delete: `client/lib/services/storage/runtime_storage_context.dart`
- Modify: 任何残留 import
- Create: `client/test/services/storage/p2_clean_state_test.dart`

**Interfaces:** 终态——无 `RuntimeStorageContext`、无 `.current`、无委派桥。

- [ ] **Step 1: 确认零残留**

```bash
cd client && grep -rn "RuntimeStorageContext" lib --include=*.dart || echo "(clean)"
```
若有残留（应只剩 Task 12 的桥与其 `bindForMigration` 调用），改其为 `registry.home()`/`forTarget` 后删除文件。

- [ ] **Step 2: 删除文件 + 桥**

```bash
cd client && git rm lib/services/storage/runtime_storage_context.dart
```
删 app_shell 的 `RuntimeStorageContext.bindForMigration` 调用。`parseWslDistro`（若仍被引用）迁到一个工具位（或随 Phase A 已删）。

- [ ] **Step 3: 终态 grep 守卫**

```bash
cd client && for s in "RuntimeStorageContext" "\.current" "StorageRoots" "connectionMode" "windowsStorageBackend" "foldersFromLegacyJson"; do
  echo "== $s =="; grep -rn "$s" lib --include=*.dart || echo "  (clean)"; done
```
Expected: 各 `(clean)`（`.current` 若被无关类占用需甄别）。

- [ ] **Step 4: 全量验收**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: CLEAN + PASS。

- [ ] **Step 5: 手验金路径**（CI 不覆盖，文档化）：桌面 local 启动；Android(home=ssh) 等价归一；工作区 A(local)+B(ssh) 并存、互不影响；拔远程机 → 项目列表/团队配置仍可读、仅 B 会话启动失败。

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: delete RuntimeStorageContext singleton; P2 clean end state"
```

---

## Self-Review

**Spec coverage（P1+P2 合并稿）:**
- §2 P1 home 权威/targets.json/bootstrap/UI/删旋钮 → Phase A (Task 1–8) ✅
- §3 清脚手架（预备 folders + P0） → Phase A Task 7 + Task 4 ✅
- §4 去单例 RuntimeContext/Resolver/Registry → Task 10/11 ✅
- §5 控制面/工作面拆分 + 45 处审计 → Task 12（AppStorage 转发）+ 13/14/15（分批迁移）+ 17（工作面解析） ✅
- §5.1 远程离线项目列表可读 → Task 11 测试 + Task 17 ✅
- §6 §10 单例迁移清单（AppStorage 转发/layout 拆/StorageRoots 退役/审计/dart:io/readSymlinkTarget） → Task 9/12/16 + 13–15 ✅
- §7 每目录 target 解析 → Task 17 ✅
- §8 文件清单 → 各任务 ✅
- §9 测试策略（金标准等价、隔离、离线可读、grep 守卫） → Task 10/11/17/18 ✅
- §10 P3 排除 → Global Constraints 强制 ✅

**Placeholder scan:** Task 13–15 的迁移按"控制面→AppStorage、工作面→forTarget"逐文件分类，给了确切文件清单与判定依据；Task 17 给了 workspaceTarget 解析骨架与确切测试。委派桥（Task 12）显式标注"transient migration sequencing, removed Task 18，非兼容"。核心新类（Context/Resolver/Registry/AppStorage/Sftp）带完整代码。

**Type consistency:** `RuntimeContext.{filesystem,paths,cwd,appDataRoot,workspace,layout}`、`RuntimeContextResolver.resolve(target,{sshProfile})`、`RuntimeContextRegistry.{home,forTarget,dispose,rebindHome,ensureHome}`、`AppStorage.{bind,fs,paths,cwd}`、`workspaceTarget(ws)` 跨任务一致。复用 Phase A 的 `homeTargetFromId`/`defaultTargetResolver`/`runtimeKindOfId`。

**零兼容终态守卫:** Task 18 grep 守卫强制无 RuntimeStorageContext/.current/StorageRoots/旧旋钮/foldersFromLegacyJson。排序（建抽象→AppStorage 转发+委派桥→分批迁移→工作面解析→删单例与桥）保每任务 analyze+test 绿。委派桥是同 PR 内重构排序、最终删除，非向后兼容。
