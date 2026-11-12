# 远端 rewind / fork 可行性设计（work-plane rewind，复用 GitCommandRunner）

- 日期：2026-11-12（v2，架构定稿）
- 状态：可行性方案（待实现）
- 关联：`2026-11-03-session-rewind-fork-design.md`、`2026-11-04-user-message-branches-design.md`、`2026-11-11-mobile-chat-message-actions-design.md`

## 1. 结论

**可行，且不需要新造执行层。** 项目已有完整的「在任意机器上跑 git / 读写文件」抽象：

- `RuntimeContext` —— 一台机器的身份（`filesystem` + `layout` + `appDataRoot` + `target`）。
- `Filesystem` —— local / WSL / SFTP 三种实现。
- `GitCommandRunner` —— `LocalGitCommandRunner` / `WslGitCommandRunner` / `RemoteGitCommandRunner`，带 `isAvailable` 探测（远端按 host 缓存）与 `gitCommandRunnerForContext(ctx)` 工厂。

rewind 现在完全绕开了它们，直接用 `dart:io` + 本地 `Process.start`，所以只在「home == work 且本地」时成立。

**目标架构**：让 rewind 跟随 **work plane**，并复用 `Filesystem` + `GitCommandRunner`：

1. resolve 出 seat 的 work-plane `RuntimeContext`；
2. `SeatRewindStore` 变成无 I/O 的纯域，只依赖 `GitCommandRunner` + `Filesystem` + `pathContext`；
3. 给 `GitCommandRunner` 增加 `runRaw / runToFile / runScript / probe` 四个方法（实现三种后端）；
4. 策略从「拒绝 mobile / 非 local」改为「work plane 有 git 且版本满足」；
5. 删除 `RewindForkService` 的 `!seat.localRuntime` 硬抛。

这样 WSL 免费获得远端能力（`WslGitCommandRunner` 已存在），未来新后端只需补 `Filesystem` + `GitCommandRunner`。

UI 无需再改：长按菜单的「编辑 / fork / 版本」和点击气泡编辑已由 `onEditUserMessage != null` / `version != null` 驱动，rewind 一通就亮。

## 2. 目标 / 非目标

**目标**

- work plane 为 SSH / Termux（Android 的 home）时，完成 checkpoint、版本切换、编辑重发、fork。
- 桌面端本地行为完全不变。
- 目标机没有 git / 版本过旧 / 离线时保持禁用，不影响聊天主流程。

**非目标**

- 多人 seat 的 checkpoint 对齐（`kMixedSeatRewindEnabled` 仍为 false）。
- rewind 用户项目 worktree（只动 session runtime 目录）。
- 删除旧 checkpoint、解析 CLI transcript 格式。
- 跨客户端并发协调（v1 依赖 git ref 原子性，进程内 `RewindWorkGate`）。

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

`isMobilePlatform()` = `Platform.isAndroid || Platform.isIOS`；`gitOnPath()` 在移动端直接 false（`client/lib/services/cli/git_on_path.dart:4-9`）。

### 3.2 store 绕开了所有抽象

`SeatRewindStore`（`client/lib/services/chat/rewind/seat_rewind_store.dart`，909 行）直接 `dart:io` + `Process.start`：

| 类别 | 位置 | 调用 |
|---|---|---|
| 目录/文件存在 | `:114` `:236` `:253` `:313` | `Directory(...).exists()` / `existsSync()` |
| 建目录 / 写文件 | `:119` `:133-135` | `Directory.create`、`File.writeAsString` |
| 删文件 / 删链接 | `:279` `:711-713` `:768` | `File.delete` / `deleteSync`、`Link.delete` |
| 目录遍历 / 类型 | `:500-506` `:781-812` | `FileSystemEntity.type`、`Directory.list(followLinks:false)` |
| 写 blob 到文件 | `:708-720` `:726-763` | `File.parent.create`、`openWrite`、`Process.start` 流式 pipe |
| 执行 git | `:829-875` | `Process.start(gitExecutable, args, workingDirectory, environment)` |

此外 `SeatRewindStore.forSession` 用 **home** layout（`chat_cubit.dart:448-453` 的 `layout: () => _storage.context.layout`），而 session runtime 目录实际按 **work plane** 解析（`session_lifecycle_service.dart:1352-1357`、`_resolveRoots` `:1480-1504`）。

### 3.3 原设计明确排除

`2026-11-03-session-rewind-fork-design.md:28-36` 把「agent/runtime 在另一台机器（SSH work plane）」和 Android 列为 non-goal；`:132` 说明 SSH seat 不显示 fork/version。

## 4. 已具备的能力（复用清单）

| 能力 | 位置 | 用途 |
|---|---|---|
| `RuntimeContext` | `services/storage/runtime_context.dart:17-90` | 机器身份：`filesystem`、`layout`、`appDataRoot`、`target`、`storageIsRemote`、`remoteFileStore` |
| `Filesystem` | `services/io/filesystem.dart:74-130` | `stat`/`lstat`、`ensureDir`、`removeRecursive`（文件/目录/链接）、`writeString`、`writeBytes`、`atomicWrite`、`listDir`、`readSymlinkTarget`、`listDirRecursive` |
| `SftpFilesystem` | `services/io/sftp_filesystem.dart:8-16` | POSIX pathContext，`isRemote == true` |
| `HostOneShotRunner` | `services/host/host_one_shot_runner.dart:25-147` | local / WSL / SSH 一次性执行 |
| `GitCommandRunner` | `services/git/git_command_runner.dart:33-290` | `isAvailable`（远端按 host 缓存）、`runInDirectory(dir, args, {environment})` |
| `gitCommandRunnerForContext` | `services/git/git_command_runner.dart:99-116` | `RuntimeContext` → runner |
| `hostOneShotRunnerForContext` | `services/host/host_one_shot_runner_for_context.dart` | `RuntimeContext` → runner |
| `HostShellArgv` / `HostRunRequest` | `services/host/` | argv-safe 引号、env、cwd |
| work-plane 解析 | `session_lifecycle_service.dart:1549-1557` `resolveWorkContextForTargetId` | target → `RuntimeContext` |
| `RemoteFileStore.execShell/startShell` | `services/storage/remote_file_store.dart:490-505` | 远端 shell / 流式 exec |

结论：**执行与文件两层已经存在，rewind 只需要接上去。**

## 5. 目标架构

```
UI（已解耦：branches / onEditUserMessage）
        │
SeatRewindController · RewindWorkGate · checkpoint trackers · policy
        │
SeatRewindStore（纯域：refs / tree / checkpoint / restore / fork；零 dart:io）
        │
GitCommandRunner（runRaw / runToFile / runScript / probe）
        │
RuntimeContext（work plane） ── Filesystem（local / WSL / SFTP）
        │
SeatRuntimeResolver（seat → RuntimeContext，缓存）
RewindCapability（isAvailable + version + batch/stream，缓存）
```

四个原则：

1. **work plane 是唯一来源**：`SeatRuntimeResolver` 解析 seat → `RuntimeContext`；store 的 `layout`/`fs`/`git` 全部来自它，不读 home layout。
2. **能力驱动**：policy 读 `RewindCapability`（`isAvailable` + `version` + 可选能力），不再判断 `Platform` 或 `RuntimeKind`。
3. **域与 I/O 分离**：`SeatRewindStore` 不 `import 'dart:io'`，只依赖 `GitCommandRunner` + `Filesystem` + `p.Context`。
4. **批量/流式是 runner 能力**：远端一次 exec 跑完 git 序列；大 blob 用宿主机重定向。

## 6. `GitCommandRunner` 扩展（唯一新增接口）

```dart
class GitRawResult {
  const GitRawResult({required this.exitCode, required this.stdout, required this.stderr});
  final int exitCode;
  final List<int> stdout; // 原始字节：showFile 需要区分二进制
  final String stderr;
}

class GitCapability {
  const GitCapability({required this.available, this.version, this.pathspecFromFile = false});
  final bool available;
  final String? version;
  final bool pathspecFromFile;
}

abstract interface class GitCommandRunner {
  Future<bool> get isAvailable;
  Future<GitCommandResult> runInDirectory(String dir, List<String> args, {Map<String, String>? environment});

  // 新增
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
  });

  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
  });

  Future<GitCapability> probe();
}
```

实现要点：

- `runRaw`
  - local：`Process.run(git, args, stdoutEncoding: null)`（拿 bytes）。
  - WSL：`Process.run('wsl.exe', [...], stdoutEncoding: null)`。
  - remote：`execShell`（`SSHRunResult.stdout` 是 bytes）。
  - 不使用 `-C`，由调用方传 `--git-dir/--work-tree`。
- `runToFile`
  - local / WSL：`Process.start`，stdout pipe 到本地文件（现有 `_runGitToFile` 逻辑）。
  - remote：`execShell` 跑 `<git args> > <quoted dest>`，数据不出宿主。
- `runScript`
  - local：POSIX `sh -lc`；Windows 本地退化为「按行顺序 runRaw」（记录限制）。
  - WSL：`wsl.exe sh -lc`。
  - remote：`execShell`。
- `probe`
  - `git --version` 解析版本；探测 `--pathspec-from-file`（`git add -h` 或版本阈值）。
  - 缓存键：host id + git executable；提供 `debugReset...`。

`GitCommandResult` 保持不变（Text 输出），`runRaw` 是新增字节通道。`runInDirectory` 保留给现有 Git UI 使用。

## 7. `SeatRewindStore` 改造

```dart
final class SeatRewindStore {
  SeatRewindStore({
    required this.gitDir,
    required this.workTree,
    required this.target,
    required this.git,   // GitCommandRunner
    required this.fs,    // Filesystem
    this.commandTimeout = const Duration(seconds: 30),
  });

  final GitCommandRunner git;
  final Filesystem fs;
  p.Context get paths => fs.pathContext;
}
```

- `_repoArgs` 不变。
- 所有 `dart:io` → `fs.*`（`stat`/`lstat`/`ensureDir`/`writeString`/`removeRecursive`/`listDir`）。
- 所有 git → `git.runRaw` / `git.runToFile` / `git.runScript`。
- `SeatRewindStore.forSession` 增加 `required RuntimeContext context`：
  ```dart
  factory SeatRewindStore.forContext({
    required RuntimeContext context,
    required String workspaceId,
    required String sessionId,
    required SeatRewindTarget target,
    String? gitExecutable,
    Duration commandTimeout = const Duration(seconds: 30),
  }) => SeatRewindStore(
    gitDir: context.layout.pathContext.join(
      context.layout.workspace.sessionDir(workspaceId, sessionId),
      'rewind', target.seatKey,
    ),
    workTree: context.layout.workspace.sessionRuntimeDir(workspaceId, sessionId),
    target: target,
    git: gitCommandRunnerForContext(context, gitExecutable: gitExecutable),
    fs: context.filesystem,
    commandTimeout: commandTimeout,
  );
  ```
- 保留 `SeatRewindStore.local(...)` 便捷构造（`LocalGitCommandRunner()` + `LocalFilesystem()`），现有测试最小改动。
- 同步调用改 async：`:236` `:253` `:278-279` `:313` 的 `existsSync/deleteSync`。
- `Uri.file(sourceGitDir)`（`:575`）→ 端口按 `paths.style` 处理：POSIX 直接用原路径。

## 8. 策略、解析与能力

### 8.1 `SeatRuntimeResolver`

新增 `client/lib/services/chat/rewind/seat_runtime_resolver.dart`：

```dart
final class SeatRuntimeResolver {
  SeatRuntimeResolver({
    required Future<RuntimeContext> Function(RuntimeTarget target) resolve,
  });

  Future<RuntimeContext> forSeat({
    required AppSession session,
    required String memberId,
    required RuntimeTarget workTarget,
  });
  void invalidate(String targetId);
}
```

- 内部按 `target.id` 缓存 `RuntimeContext`；home 代际/重连时 `invalidate`。
- 基于 `SessionLifecycleService.resolveWorkContextForTargetId`。

### 8.2 `RewindCapability`

新增 `client/lib/services/chat/rewind/rewind_capability.dart`：把 `GitCommandRunner.isAvailable` + `probe()` 汇总为：

```dart
final class RewindCapability {
  final bool available;
  final String? gitVersion;
  final bool pathspecFromFile;
  final bool batchScript;
  final bool streamingToFile;
}
```

按 host 缓存；`git==null` / 版本过旧 → `available=false`。

### 8.3 策略

`SeatRewindPolicy.evaluate` 保持**同步**（UI 与宿主大量同步调用），改为读缓存：

- 输入：work-plane `RuntimeContext`（若未解析 → `denied(workPlaneNotReady)`）、`RewindCapability`。
- 拒绝项：`mixedSeatsDisabled`、`workPlaneNotReady`、`gitMissing`、`gitTooOld`、`unsupportedBackend`（Windows 远端）。
- **删除** `mobilePlatform` / `remoteRuntime`。

`SessionHistoryRewindHost._reload` 先 `await resolver.forSeat(...)` + `await capability.for(ctx)`，再 `policy.evaluate`；`build` 读已缓存值。

### 8.4 `RewindForkService`

删除 `!seat.localRuntime` 抛错（`rewind_fork_service.dart:49-51`）。`_CubitSeatProcess.stopAndWait/relaunch` 已按 ACP/PTY 分派并支持远端（`chat_rewind_adapters.dart:37-108`）。

## 9. 性能与批处理

`commitTurn` 的远端代价必须收敛：

1. `_includedRuntimeFiles` → 远端用一次 `find <runtime> -type f`（`-prune` 排除 `plugins/skills/node_modules/cache`），替代 SFTP 递归。
2. `_dropStaleSeatIndexEntries` → 远端跳过（v1 权衡，记录）；或一次 shell 批量 `test -f`。
3. `commitTurn` 的 add → write-tree → commit-tree → 3×update-ref 合并为一个 `runScript`（一次 exec）。
4. `showFile` / `_writeRawBlob` 用 `runRaw` / `runToFile`，大文件不出宿主。

目标：正常 turn 的远端 checkpoint ≤ 2-3 次 exec。

## 10. 风险与开放问题

| 风险 | 说明 | 缓解 |
|---|---|---|
| 性能 | 每 turn 远端 exec | §9 批处理；必要时只在 turn 结束且前台 |
| 网络中断 | checkpoint 失败/半写 | 失败仅日志；`RewindWorkGate` 串行；下次以 `checked-out` 为父 |
| 并发客户端 | 进程内锁不跨端 | v1 接受；依赖 git ref 原子性；记录限制 |
| 远端 git 版本 | 无 `--pathspec-from-file` | `probe` 探测；旧版回退逐文件 |
| Windows 远端 home | 路径/命令差异 | v1 `unsupportedBackend` 拒绝 |
| WSL | 已有 runner，但路径/工作区需验证 | Phase 1 顺带验证；有问题则临时拒绝 |
| 大文件 | SQLite/transcript | `runToFile` 宿主侧重定向 |
| context/capability 缓存 | 同步 policy 读缓存可能短暂未就绪 | `workPlaneNotReady` → UI 先禁用，`_reload` 重试 |
| `Uri.file` | Windows 本地路径 | `paths.style` 分支 |

**开放问题**

1. work-plane context 在会话连接时是否总能解析（SSH 冷启动缓存）？
2. capability 探测放在 home 连接还是首次进入会话？失效条件？
3. `runScript` 在 Windows 本地是否要做（还是退化为顺序执行）？
4. 远端跳过 `_dropStaleSeatIndexEntries` 是否可接受（需回归：删文件后 checkpoint，restore 是否残留）？
5. Android 是否恒为「home == work」？若存在 local home + SSH work，按 capability 自然拒绝。

## 11. 分阶段落地

| 阶段 | 内容 | 产物 | 风险 |
|---|---|---|---|
| **Phase 0** | `SeatRewindStore` 改依赖 `GitCommandRunner` + `Filesystem`；本地注入现有实现；纯重构 | 现有 rewind 测试全绿 | 低 |
| **Phase 1** | `runRaw/runToFile/runScript/probe` + `SeatRuntimeResolver` + `RewindCapability` + policy/fork 改造 | 桌面 SSH home 可用；WSL 顺带验证 | 中 |
| **Phase 2** | 删除 mobile 拒绝；Android 真机验证 | 移动端「编辑/fork/版本/点击气泡编辑」自动亮起 | 中 |
| **Phase 3** | 体验打磨（可选） | UI | 低 |

Phase 0 可单独合并，行为不变。

## 12. 测试计划

- **Phase 0**：`seat_rewind_store_test.dart`（513 行）、`seat_branches_test.dart`、`rewind_fork_service_test.dart`、`seat_rewind_policy_test.dart` 全绿；`SeatRewindStore.local(...)` 保持测试构造方式。
- **Phase 1**：
  - `GitCommandRunner` 新方法单测：local 用假 `Process` runner；remote 用假 `execShell`，断言 argv、env、stdin、重定向。
  - `SeatRuntimeResolver` / `RewindCapability` 单测：缓存、失效、无 git、版本过旧。
  - policy 单测：local+git → allowed；remote+git → allowed；no git → denied；WSL → 视验证结果；未解析 → `workPlaneNotReady`。
  - 手动 e2e（桌面 + SSH home）：checkpoint → 版本切换 → 编辑重发 → fork。
- **Phase 2**：Android 真机（SSH home）：长按菜单「编辑/版本」、点击气泡弹面板 + 压暗、发送后旧轮次被替换。
- 按 `AGENTS.md`：`flutter analyze` → 单文件 `dart run tool/run_tests.dart` → 全量一次。

## 13. 影响面

新增：
- `client/lib/services/chat/rewind/seat_runtime_resolver.dart`
- `client/lib/services/chat/rewind/rewind_capability.dart`
- 测试：`rewind_io` 相关改为 runner 测试；`seat_runtime_resolver_test.dart`、`rewind_capability_test.dart`

修改：
- `services/git/git_command_runner.dart`（+4 方法 × 3 实现）
- `seat_rewind_store.dart`（去 `dart:io`，注入 runner/fs）
- `seat_rewind_policy.dart`（capability 驱动，denial 调整）
- `rewind_fork_service.dart`（去 `localRuntime`）
- `chat_cubit.dart`（resolver/capability 接线、策略构造）
- `seat_rewind_controller.dart`（传 context）
- `seat_pty_checkpoint_tracker.dart` / `acp_runtime_attach.dart`（policy 同步读缓存，通常不变）
- 测试：上述 rewind 测试

不动：
- UI（长按菜单、编辑面板、`session_history_thread.dart`）
- `ai_message_ui` / `shared_ui` / vendored 包
- 用户项目 worktree

## 14. 待确认

1. 是否接受 Phase 0 先合入（纯重构）？
2. capability 探测时机（home 连接 vs 首次进入会话）？
3. Windows 远端 home 是否明确不支持？
4. 远端是否接受跳过 `_dropStaleSeatIndexEntries`？
5. Windows 本地是否实现 `runScript`，还是退化为顺序执行？
