# 远端 rewind / fork 可行性设计（work-plane rewind）

- 日期：2026-11-12
- 状态：可行性方案（未实现，待评审）
- 关联：`2026-11-03-session-rewind-fork-design.md`、`2026-11-04-user-message-branches-design.md`、`2026-11-11-mobile-chat-message-actions-design.md`

## 1. 结论

**可行。** 但正确目标不是「把 rewind 从 home 平面搬到远端」，而是「**让 rewind 跟随 work plane**」：rewind 的私有 git 仓库和 work tree（session runtime 目录）本来就应该落在 **agent 实际运行的那台机器**上，而不是固定用 home 平面的 layout。当前实现用 home 平面 layout + 本地 `dart:io` / 本地 `git`，所以只在「home == work 且本地」时成立。

需要做三件事：

1. 抽出 `RewindIo` 端口，把 `SeatRewindStore` 里所有 `dart:io` / `Process.start` 换成端口（Phase 0，纯重构，本地行为不变）。
2. 增加远端实现：`Filesystem`（已有 `SftpFilesystem`）+ `RemoteFileStore.runHost/startShell`（已有 argv-safe 远端执行）+ 远端 `git` 能力探测。
3. 策略从「拒绝 mobile / 非 local」改为「**目标机器支持 git 且 work-plane context 可解析**」；`RewindForkService` 去掉 `!seat.localRuntime` 硬抛。

Android 的 home 与 work 都是同一台 SSH 机器，所以 Phase 1 完成后手机自动具备条件；Phase 2 只需放开 `mobilePlatform` 拒绝并做设备验证。UI 侧（长按菜单的「编辑 / fork / 版本」、点击气泡编辑）**无需再改**：它们已经由 `onEditUserMessage != null` / `version != null` 驱动，rewind 一旦可用就会亮起。

最大风险：**性能**。当前 `commitTurn` 有逐文件 stat（`_dropStaleSeatIndexEntries`）和本地目录遍历（`_includedRuntimeFiles`）；直译成远端会导致 N 次 SSH round-trip。必须批处理（见 §8）。

## 2. 目标 / 非目标

**目标**

- 在 work plane 为 SSH / Termux（Android 的 home）时，完成 checkpoint、版本切换、编辑重发、fork。
- 桌面端本地行为完全不变。
- 失败可降级：目标机没有 git / 离线时保持禁用，不影响聊天主流程。

**非目标（本方案不改）**

- 同步/对齐多人 seat 的 checkpoint（`kMixedSeatRewindEnabled` 仍为 false）。
- rewind 用户项目 worktree（只动 session runtime 目录）。
- WSL 目标的 rewind（路径与 `wsl.exe` 执行未覆盖，保持禁用）。
- 删除旧 checkpoint、解析 CLI transcript 格式。

## 3. 现状：为什么现在不行

### 3.1 两道硬门禁

1. `SeatRewindPolicy.evaluate`（`client/lib/services/chat/rewind/seat_rewind_policy.dart:51-86`）：
   - `isMobile()` → `denied(mobilePlatform)`（`:63-65`）
   - `launchTarget.kind != RuntimeKind.local` → `denied(remoteRuntime)`（`:66-69`）
   - `!gitAvailable()` → `denied(gitMissing)`（`:70-72`）
2. `RewindForkService.rewind`（`client/lib/services/chat/rewind/rewind_fork_service.dart:49-51`）：
   ```dart
   if (!seat.localRuntime) {
     throw StateError('Cannot rewind a remote runtime');
   }
   ```
   `localRuntime` 来自 `_CubitSeatProcess`（`client/lib/cubits/chat_rewind_adapters.dart:19-26`），同样是 `RuntimeKind.local` 判断。

`isMobilePlatform()` 就是 `Platform.isAndroid || Platform.isIOS`；`gitOnPath()` 在移动端直接返回 false（`client/lib/services/cli/git_on_path.dart:4-9`）。

### 3.2 store 全是本地 I/O

`SeatRewindStore`（`client/lib/services/chat/rewind/seat_rewind_store.dart`，909 行）没有任何 `Filesystem` 抽象，直接 `dart:io`：

| 类别 | 位置 | 调用 |
|---|---|---|
| 目录/文件存在 | `:114` `:236` `:253` `:313` | `Directory(...).exists()` / `existsSync()` |
| 建目录 / 写文件 | `:119` `:133-135` | `Directory.create`、`File.writeAsString` |
| 删文件 / 删链接 | `:279` `:711-713` `:768` | `File.delete` / `deleteSync`、`Link.delete` |
| 目录遍历 / 类型 | `:500-506` `:781-812` | `FileSystemEntity.type`、`Directory.list(followLinks:false)` |
| 写 blob 到文件 | `:708-720` `:726-763` | `File.parent.create`、`openWrite`、`Process.start` 流式 pipe |
| 执行 git | `:829-875` | `Process.start(gitExecutable, args, workingDirectory, environment)` |

## 4. 关键架构事实：runtime 在 work plane，不在 home plane

- session 的 runtime 目录按 **workspace 的工作机**解析：`session_lifecycle_service.dart:1352-1357` 用 `_resolveRoots(session: session)` → `_resolveRoots`（`:1480-1504`）在 `session != null` 时走 `_workContextResolver(target)`，即 work-plane `RuntimeContext`。
- 但 rewind 的 store 用 **home** layout：`ChatCubit` 构造策略时传 `layout: () => _storage.context.layout`（`client/lib/cubits/chat_cubit.dart:448-453`），`SeatRewindStore.forSession` 用它拼 `sessionDir(...)/rewind/...` 和 `sessionRuntimeDir(...)`（`seat_rewind_store.dart:74-93`）。
- 当 work target ≠ home target（例如本地 home + SSH 工作区）时，store 指向错误的机器/空目录；这正是 `launchTarget.kind != local` 拒绝存在的原因。
- 原设计文档也明确把「agent 与 runtime 在另一台机器（SSH work plane）」和 Android 列为 non-goal（`2026-11-03-session-rewind-fork-design.md:28-36`、`:132`）。

**结论：正确改法是让 rewind 使用 work-plane `RuntimeContext`**（它的 `layout`、`filesystem`、`remoteFileStore`、`appDataRoot`），而不是 home context。这样：

- 桌面 + 本地工作区 → 本地 `dart:io` / 本地 git（与现状一致）。
- 桌面 + SSH 工作区 → 远端 home/work 同一台 → SFTP + 远端 git。
- Android（home 与 work 均为 SSH 同一台）→ 同远端路径。

## 5. 已具备的远端能力

- `RuntimeContext` 暴露 `filesystem`、`appDataRoot`、`layout`、`storageIsRemote`、`remoteFileStore`（`client/lib/services/storage/runtime_context.dart:17-80`）。
- `Filesystem` 接口已覆盖：`stat` / `lstat`(扩展) / `ensureDir` / `removeRecursive`(文件、目录、链接均可，`local_filesystem.dart:94-106`) / `writeString` / `writeBytes` / `atomicWrite` / `listDir` / `readSymlinkTarget` / `copyFile` / `listDirRecursive` 等（`client/lib/services/io/filesystem.dart:74-130`）。
- `SftpFilesystem` 是 POSIX pathContext（`sftp_filesystem.dart:8-16`），`isRemote == true`。
- 远端执行：
  - `RemoteFileStore.runHost(HostRunRequest)` —— **argv-safe**（`RemoteHostOneShotRunner` + `HostShellArgv.command`，`remote_file_store.dart:490-497`、`host_one_shot_runner.dart:129-148`），支持 executable / arguments / workingDirectory / environment。
  - `RemoteFileStore.execShell(String)` —— 原始 shell（`remote_file_store.dart:499-501`）。
  - `RemoteFileStore.startShell(String)` —— 流式 exec（`:503-505`），可等 `exitCode`。
  - `RemoteFileStore.removeRecursive` = `rm -rf --`（`:316-322`）。

这些足以承载「在 work plane 上跑 git + 读写远端文件」，不需要新造传输层。

## 6. 差距清单（gap analysis）

| # | 差距 | 影响 | 处理 |
|---|---|---|---|
| G1 | store 用 home layout | 路径指向错误机器 | 用 work-plane `RuntimeContext` 构造 store |
| G2 | store 直连 `dart:io` | 远端不可用 | 抽 `RewindIo` 端口 |
| G3 | 同步 `Directory.existsSync` / `deleteSync` | 远端无法同步 | 端口全部 async |
| G4 | `Process.start` 本地执行 git | 远端不可用 | 端口 `runGit` → 本地 Process / 远端 `runHost` |
| G5 | `_runGitToFile` 本地流式落盘 | 远端不可用 | 远端用 shell 重定向 `> dest`（在宿主机流式），或 `startShell` |
| G6 | `Uri.file(sourceGitDir)`（`:575`） | 远端 POSIX 路径不适用 | 端口提供路径规范化；POSIX 直接用原路径 |
| G7 | 逐文件 `FileSystemEntity.type`（`:500-506`） | 远端 N 次 round-trip | 远端批处理（一次 shell 或 `find`） |
| G8 | 目录遍历 `Directory.list`（`:781-812`） | 远端 N 次 round-trip | 远端一次 `find` 拿文件列表 |
| G9 | 策略拒绝 mobile / 非 local | 功能不可达 | 改为能力探测（见 §7.3） |
| G10 | `RewindForkService` 的 `localRuntime` 硬抛 | 远端 fork/switch 被拒 | 删除该判断（保留 policy 的能力判断） |
| G11 | 同步 `gitAvailable` | 远端探测是异步 | 连接时异步探测并缓存，policy 读缓存 |
| G12 | 测试用本地 `gitDir` 构造 store | 构造签名变化 | 保留 `SeatRewindStore.local(...)` 便捷构造 |

## 7. 设计

### 7.1 `RewindIo` 端口

新增 `client/lib/services/chat/rewind/rewind_io.dart`：

```dart
enum RewindEntityKind { file, directory, symlink, notFound }

final class RewindFsEntry {
  final String name;
  final RewindEntityKind kind;
}

final class RewindExecResult {
  final List<int> stdout;
  final String stderr;
  final int exitCode;
}

abstract interface class RewindIo {
  bool get isRemote;
  p.Context get pathContext;
  String get gitExecutable;

  // 文件系统
  Future<bool> dirExists(String path);
  Future<bool> fileExists(String path);
  Future<RewindEntityKind> kind(String path); // lstat 语义
  Future<void> ensureDir(String path);
  Future<void> writeString(String path, String content);
  Future<void> deletePath(String path); // 文件 / 链接 / 目录
  Future<List<RewindFsEntry>> listDir(String path); // 不递归，含 kind
  Future<List<String>> listFilesRecursive(String root,
      {required bool Function(String relative) mayEnter}); // 供 _includedRuntimeFiles

  // git
  Future<RewindExecResult> runGit(
    List<String> args, {
    Map<String, String>? environment,
    String? stdinText,
  });
  Future<void> runGitToFile(List<String> args, String destPath);
}
```

- `LocalRewindIo`：把现有 `dart:io` 代码原样搬进来（`Process.start`、`Directory.list`、`File.writeAsString`…），行为零变化。
- `RemoteRewindIo`：持有 `Filesystem` + `RemoteFileStore`。
  - `runGit` → `runHost(HostRunRequest(executable: io.gitExecutable, arguments: args, environment: env, workingDirectory: workTree))`，stdin 用 `runHostWithStdin` / `runOnStorageWithStdin`（若不足则在端口层用 `startShell` 写 stdin）。
  - `runGitToFile` → `startShell('<git args> > <dest>')`，argv 用 `HostShellArgv.command`，`dest` 用 `shellSingleQuote`；避免把大 blob 拉回设备。
  - `listFilesRecursive` → 一次 `find <root> -type f`（带 `-prune` 排除 `plugins/skills/node_modules/cache`），比 SFTP 递归快一个量级。
  - `kind` → `Filesystem.stat` / `lstat`。
- `RewindIo.forContext(RuntimeContext ctx, {String gitExecutable = 'git'})`：`ctx.storageIsRemote ? RemoteRewindIo(...) : LocalRewindIo(...)`。

### 7.2 `SeatRewindStore` 改造

- 构造函数：`SeatRewindStore({required this.gitDir, required this.workTree, required this.target, required RewindIo io})`；
  - 保留 `SeatRewindStore.local({...})` 供现有测试。
- `_repoArgs` 不变。
- 所有 `dart:io` 调用替换为 `io.*`；所有 git 调用走 `io.runGit` / `io.runGitToFile`。
- `SeatRewindStore.forSession` 增加 `required RuntimeContext context`，内部用 `context.layout` 与 `RewindIo.forContext(context)`。
- `_dropStaleSeatIndexEntries`：远端实现改为一次 shell（`ls-files -z | while read ... test -f`）或接受多一次 round-trip；本地不变。
- `_includedRuntimeFiles`：远端走 `listFilesRecursive`。

### 7.3 work-plane 解析与能力探测

- `SeatRewindPolicy` 构造改为：
  ```dart
  SeatRewindPolicy({
    required Future<RuntimeContext> Function(AppSession, String?) workContextFor,
    required bool Function(RuntimeTarget) gitAvailable, // 读缓存
    ...
  })
  ```
  `evaluate` 需要 work context，但当前是同步。两条路：
  1. **缓存优先**（推荐）：会话连接/切换时异步 `resolveWorkContextForTargetId(target.id)` 并缓存，`evaluate` 读缓存；未缓存时返回 `denied(homeNotReady)`。
  2. 把 `rewindActionsAllowed` / `evaluate` 改成 `Future`，所有调用点（`SessionHistoryRewindHost._reload` 已是 async）适配。
- git 能力探测：
  - local → `gitOnPath()`。
  - remote → 每台机器一次 `runHost(git --version)`，缓存在 home/context 代际上；`gitAvailable(target)` 只读缓存。
- `RewindDenial` 调整：
  - 保留 `mixedSeatsDisabled`。
  - 删除 `mobilePlatform` / `remoteRuntime` 的语义，改为 `workPlaneUnsupported`（WSL 等）与 `gitMissing`、`homeNotReady`。

### 7.4 `RewindForkService`

删除 `!seat.localRuntime` 抛错（`rewind_fork_service.dart:49-51`）。理由：`_CubitSeatProcess.stopAndWait/relaunch` 本身已经按 ACP/PTY 分派，支持远端 seat（`chat_rewind_adapters.dart:37-108`）。是否可停止应由 policy 决定，而不是再判一次 `localRuntime`。

### 7.5 写入侧（自动继承）

- PTY：`SeatPtyCheckpointTracker.checkpointTurn` → `host.ptyCommitCheckpoint` → `store.commitTurn`（`seat_pty_checkpoint_tracker.dart:60-100`、`chat_cubit.dart:1642`）。
- ACP：`acp_runtime_attach._turnCheckpointCallback` → `store.commitTurn`（`acp_runtime_attach.dart:655-695`）。
- 版本列表：`readSeatBranches(store:)`（`seat_branches.dart:43`）。

这三处只依赖 store，store 换 io 后自动获得远端能力；无需各自加分支。

## 8. 性能与批处理

每个 turn 结束都会跑一次 `commitTurn`。本地路径的代价：`ls-files` + 逐文件 stat + 目录 walk + 1 次批量 `add` + `write-tree` + `commit-tree` + 3 次 `update-ref`。

远端若逐项 round-trip，单 turn 可能到数秒。必须：

1. `_includedRuntimeFiles` → 一次 `find`（远端），而不是 SFTP 递归。
2. `_dropStaleSeatIndexEntries` → 一次 shell 批量 `test -f`；或（简化）远端跳过该检查（它是为「文件被删但 index 还在」兜底，git `add -A` 语义可覆盖）。**建议 v1 远端跳过，记为可见的权衡。**
3. `commitTurn` 的序列（add → write-tree → commit-tree → 3×update-ref）可合并成**一个 shell 脚本**，一次 exec 完成；stdin 传 pathspec。
4. `runGitToFile` 用远端重定向，数据不出宿主机。

目标：单 turn 远端 checkpoint ≤ 2-3 次 exec（正常 turn），而不是数十次。

## 9. 风险与开放问题

| 风险 | 说明 | 缓解 |
|---|---|---|
| 性能 | 每次 turn 的远端 round-trip | §8 批处理；必要时加「只在 turn 结束且 app 前台」 |
| 网络中断 | checkpoint 失败 / 半写 | 失败仅记日志、不阻塞 turn；`RewindWorkGate` 串行；下次 checkpoint 以 `checked-out` 为父 |
| 并发客户端 | 同一远端 home 多端连接时进程内锁无效 | v1 接受；依赖 git ref 原子性；记录为已知限制 |
| 远端 git 版本 | 老版本无 `--pathspec-from-file` | 现有 `on StateError` 回退保留（会退化为逐文件，仅老版本） |
| Windows 远端 home | `remoteOs == windows` 的路径/命令 | v1 保持拒绝（`workPlaneUnsupported`） |
| WSL | `WslFilesystem` 非 remote，但 `wsl.exe` 执行未覆盖 | v1 保持拒绝 |
| 大文件 | ACP 的 SQLite/transcript | `runGitToFile` 远端重定向，不经过设备内存 |
| 磁盘占用 | 每个 seat 一份私有 git 仓库在 work plane | 与本地一致；不新增策略 |
| `Uri.file` | Windows 本地路径语义 | 端口层按 `pathContext.style` 处理 |
| 依赖 context 缓存 | `evaluate` 同步读缓存，可能短暂 `homeNotReady` | `SessionHistoryRewindHost._reload` 已能重试；UI 先禁用后亮起 |

**开放问题（实现前需确认）**

1. work-plane `RuntimeContext` 是否总是能在会话连接时解析到（SSH 断线/冷启动缓存）？
2. 远端 `git --version` 探测放在 home 连接完成时，还是首次进入会话时？缓存失效条件（home 切换、重连）？
3. `runHost` 的 stdin 能力是否满足 `git add --pathspec-from-file=-` / `rev-list --stdin`；若不足，是否统一改走 `startShell`？
4. 远端跳过 `_dropStaleSeatIndexEntries` 是否可接受（需要一次回归验证：文件被删除后再 checkpoint，restore 是否残留旧文件）？
5. Android 上「home == work」是否恒成立？若存在 local home + SSH work 的组合，按 `workPlaneUnsupported` 继续拒绝即可。

## 10. 分阶段落地

| 阶段 | 内容 | 产物 | 风险 |
|---|---|---|---|
| **Phase 0** | 抽 `RewindIo` + `LocalRewindIo`，store 全量改走端口；不加任何远端能力 | 纯重构，现有 rewind 测试全绿 | 低 |
| **Phase 1** | `RemoteRewindIo` + work-plane context 解析 + git 探测 + policy 改造 + fork service 去 `localRuntime` | 桌面 + SSH work plane 可用 | 中 |
| **Phase 2** | 放开 `mobilePlatform` 拒绝；Android 设备验证 | 移动端「编辑 / fork / 版本 / 点击气泡编辑」自动亮起 | 中（性能/网络） |
| **Phase 3**（可选） | 移动端编辑体验打磨（面板定位、键盘、长按菜单顺序） | UI | 低 |

Phase 0 单独交付可以先合并，不改变任何用户可见行为。

## 11. 测试计划

- **Phase 0**：现有 `client/test/services/chat/rewind/*`（`seat_rewind_store_test.dart` 513 行、`rewind_fork_service_test.dart`、`seat_branches_test.dart`、`seat_rewind_policy_test.dart`）全绿，证明重构无行为变化。
- **Phase 1**：
  - `FakeRewindIo`：记录/回放 exec 与文件操作，单测 `SeatRewindStore` 在「远端」语义下的路径与参数（不需要真 SSH）。
  - `RemoteRewindIo` 单测：用注入的 `RemoteFileStore`/`Filesystem` fake，断言 argv-safe 命令、stdin、重定向。
  - policy 单测：local+git → allowed；remote+git → allowed；no git → denied；WSL → denied；未解析 work context → denied。
  - 手动：桌面 + SSH home 跑一轮 checkpoint → 版本切换 → 编辑重发 → fork。
- **Phase 2**：Android 真机（SSH home）：长按菜单出现「编辑 / 从版本」，版本 `1/2` 可切换；点击用户气泡弹面板 + 压暗；发送后旧轮次被替换。
- 按 `AGENTS.md`：`flutter analyze` → 单文件 `dart run tool/run_tests.dart` → 全量一次。

## 12. 影响面

新增：
- `client/lib/services/chat/rewind/rewind_io.dart`（端口 + local/remote 实现，或拆两个文件）

修改：
- `seat_rewind_store.dart`（全部 I/O 走端口，签名加 `RewindIo` / `RuntimeContext`）
- `seat_rewind_policy.dart`（work-plane context、能力探测、denial 调整）
- `rewind_fork_service.dart`（删除 `localRuntime` 抛错）
- `chat_cubit.dart`（策略构造、work context 缓存、git 探测）
- `seat_rewind_controller.dart`（`loadBranches` / `fork` 传 context）
- `seat_pty_checkpoint_tracker.dart`（若 policy 改 async，需要适配）
- `acp_runtime_attach.dart`（若 policy 改 async）
- 测试：`seat_rewind_store_test.dart`、`seat_rewind_policy_test.dart`、`rewind_fork_service_test.dart`、`seat_branches_test.dart`、新增 `rewind_io_test.dart` / `remote_rewind_io_test.dart`

不动：
- UI（长按菜单、编辑面板、`session_history_thread.dart`）——已经由 rewind 能力驱动。
- `ai_message_ui` / `shared_ui` / vendored 包。
- 用户项目 worktree。

## 13. 待确认问题（给评审）

1. 是否接受 Phase 0 先合入（纯重构）？
2. 远端 git 探测与 work-context 解析放在哪个生命周期（home 连接 vs 首次进入会话）？
3. Windows 远端 home 与 WSL 是否明确保持不支持？
4. 远端 `_dropStaleSeatIndexEntries` 是否接受跳过（性能 vs 残留文件）？
5. 移动端放开后，是否需要「checkpoint 期间不阻塞发送」的开关（性能保守策略）？
