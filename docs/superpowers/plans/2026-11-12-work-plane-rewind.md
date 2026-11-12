# Work-Plane Remote Rewind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 rewind / fork / 编辑重发跟随 work plane，在本地、WSL、SSH（含 Android 的 SSH home）上工作，并复用现有的 `GitCommandRunner` + `Filesystem`。

**Architecture:** `SeatRewindStore` 从 `dart:io` + 本地 `Process` 改为依赖 `GitCommandRunner` + `Filesystem`；为 `GitCommandRunner` 增加 `runRaw / runToFile / runScript / probe` 四个方法（local/WSL/remote 三实现）；新增 `SeatRuntimeResolver`（seat → work-plane `RuntimeContext`）与 `RewindCapability`（git 可用性/版本缓存）；策略改为 capability 驱动，删除 `mobilePlatform` / `remoteRuntime` / `!seat.localRuntime` 三处硬拒绝。

**Tech Stack:** Flutter 3.47 / Dart 3.8、`GitCommandRunner`（`services/git/`）、`HostOneShotRunner`（`services/host/`）、`Filesystem`（`services/io/`）、`RemoteFileStore`（`services/storage/`）、`RuntimeContext`。

**Spec:** `docs/superpowers/specs/2026-11-12-remote-rewind-feasibility-design.md`（已批准）。

## Global Constraints

- **Never invoke `flutter test` directly** — 一律 `cd client && dart run tool/run_tests.dart <paths/options>`。
- 内环 `flutter analyze` + 单文件 `dart run tool/run_tests.dart`；外环全量一次，后台跑。
- 桌面端本地行为完全不变；Phase 0-2 期间本地路径必须与现状逐字节一致。
- 命令注入红线：远端命令一律用 `HostShellArgv` / `shellSingleQuote` 构造，禁止字符串拼接未转义参数。
- **每次 commit 只 `git add` 本任务涉及的文件，绝对不要 `git add -A` / `git add .`。**
- 工作区原有约 50+ 个未提交/未跟踪改动属于其它并行工作，不得修改、暂存或回滚。
- 新增 UI 拆独立文件；l10n 不新增键；文本样式用 `TpTextStyles`。
- 测试文件路径与命名遵循现有 `client/test/services/chat/rewind/`、`client/test/services/git/` 风格。

---

## File Structure

| 文件 | 职责 | 动作 |
|---|---|---|
| `client/lib/services/git/git_command_runner.dart` | 跨后端 git 执行；新增 `runRaw/runToFile/runScript/probe` + `GitRawResult`/`GitCapability` | Modify |
| `client/lib/services/storage/remote_file_store.dart` | 暴露 `execShellWithStdin` | Modify |
| `client/lib/services/chat/rewind/seat_rewind_store.dart` | 纯域：注入 `GitCommandRunner` + `Filesystem`，去 `dart:io` | Modify |
| `client/lib/services/chat/rewind/seat_runtime_resolver.dart` | seat → work-plane `RuntimeContext`，缓存 | Create |
| `client/lib/services/chat/rewind/rewind_capability.dart` | git 可用性/版本/能力缓存 | Create |
| `client/lib/services/chat/rewind/seat_rewind_policy.dart` | capability 驱动，denial 调整 | Modify |
| `client/lib/services/chat/rewind/rewind_fork_service.dart` | 删除 `!seat.localRuntime` | Modify |
| `client/lib/services/chat/rewind/seat_rewind_controller.dart` | 传 work-plane context | Modify |
| `client/lib/cubits/chat_cubit.dart` | 接线 resolver/capability、策略构造 | Modify |
| `client/test/services/git/git_command_runner_test.dart` | 新方法测试 | Modify |
| `client/test/services/chat/rewind/seat_rewind_store_test.dart` | 保持本地构造，新增远端分支测试 | Modify |
| `client/test/services/chat/rewind/seat_runtime_resolver_test.dart` | 新文件 | Create |
| `client/test/services/chat/rewind/rewind_capability_test.dart` | 新文件 | Create |
| `client/test/services/chat/rewind/seat_rewind_policy_test.dart` | 更新 denial 断言 | Modify |

---

## Task 1: 扩展 GitCommandRunner —— 类型 + Local 实现

**Files:**
- Modify: `client/lib/services/git/git_command_runner.dart`
- Test: `client/test/services/git/git_command_runner_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class GitRawResult { final int exitCode; final List<int> stdout; final String stderr; bool get succeeded; }
  class GitCapability { final bool available; final String? version; final bool pathspecFromFile; static const unavailable; }
  // GitCommandRunner 新增：
  Future<GitRawResult> runRaw(List<String> args, {String? workingDirectory, Map<String,String>? environment, String? stdinText, bool allowFailure = false, Duration? timeout});
  Future<void> runToFile(List<String> args, String destPath, {String? workingDirectory, Map<String,String>? environment, Duration? timeout});
  Future<GitCommandResult> runScript(String script, {String? workingDirectory, Map<String,String>? environment, String? stdinText, Duration? timeout});
  Future<GitCapability> probe();
  ```

- [ ] **Step 1: Write the failing test**

在 `client/test/services/git/git_command_runner_test.dart` 的 `main()` 内新增：

```dart
  group('LocalGitCommandRunner raw/script/probe', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('git-runner-');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('probe reports available and version', () async {
      final runner = LocalGitCommandRunner();
      final cap = await runner.probe();
      expect(cap.available, isTrue);
      expect(cap.version, isNotNull);
    });

    test('runRaw returns bytes and honors stdin', () async {
      final runner = LocalGitCommandRunner();
      final init = await runner.runRaw(['init', '--bare', tmp.path]);
      expect(init.exitCode, 0);
      final ver = await runner.runRaw(['--version']);
      expect(utf8.decode(ver.stdout), contains('git version'));
      final bad = await runner.runRaw(['no-such-command'], allowFailure: true);
      expect(bad.exitCode, isNot(0));
      expect(bad.stderr, isNotEmpty);
    });

    test('runToFile streams stdout to a file', () async {
      final runner = LocalGitCommandRunner();
      final repo = p.join(tmp.path, 'r');
      await Directory(repo).create();
      await runner.runRaw(['init', repo]);
      await File(p.join(repo, 'a.txt')).writeAsString('hello');
      await runner.runRaw(['-C', repo, 'add', 'a.txt']);
      await runner.runRaw([
        '-C', repo, '-c', 'user.email=a@b', '-c', 'user.name=a',
        'commit', '-m', 'x',
      ]);
      final dest = p.join(tmp.path, 'blob.txt');
      await runner.runToFile(['-C', repo, 'show', 'HEAD:a.txt'], dest);
      expect(await File(dest).readAsString(), 'hello');
    });

    test('runScript runs a POSIX shell script', () async {
      final runner = LocalGitCommandRunner();
      final result = await runner.runScript('printf "ok"');
      expect(result.stdout, 'ok');
      expect(result.exitCode, 0);
    });
  });
```

补充 import：`import 'package:path/path.dart' as p;`。

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart
```
Expected: 编译失败：`GitRawResult` / `runRaw` / `runToFile` / `runScript` / `probe` 未定义。

- [ ] **Step 3: Write minimal implementation**

在 `git_command_runner.dart` 顶部（`GitCommandResult` 后）新增类型：

```dart
class GitRawResult {
  const GitRawResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
  final int exitCode;
  final List<int> stdout;
  final String stderr;
  bool get succeeded => exitCode == 0;
}

class GitCapability {
  const GitCapability({
    required this.available,
    this.version,
    this.pathspecFromFile = false,
  });
  final bool available;
  final String? version;
  final bool pathspecFromFile;
  static const unavailable = GitCapability(available: false);
}

/// Parses `git --version` output into a [GitCapability]. Shared by all runners.
GitCapability gitCapabilityFromVersion(GitRawResult result) {
  if (result.exitCode != 0) return GitCapability.unavailable;
  final text = utf8.decode(result.stdout, allowMalformed: true).trim();
  final match = RegExp(r'git version (\d+)\.(\d+)').firstMatch(text);
  final major = int.tryParse(match?.group(1) ?? '') ?? 0;
  final minor = int.tryParse(match?.group(2) ?? '') ?? 0;
  return GitCapability(
    available: true,
    version: match == null ? text : '${match.group(1)}.${match.group(2)}',
    pathspecFromFile: major > 2 || (major == 2 && minor >= 25),
  );
}
```

接口新增（`GitCommandRunner` 内）：

```dart
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  });

  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  });

  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  });

  Future<GitCapability> probe();
```

`LocalGitCommandRunner` 实现（追加到类内）：

```dart
  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async {
    final git = await _git;
    if (git == null) {
      return const GitRawResult(
        exitCode: 127,
        stdout: [],
        stderr: 'git executable not found on PATH',
      );
    }
    final process = await Process.start(
      git,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final outFuture = process.stdout.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    final errFuture = process.stderr.transform(utf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    try {
      await process.stdin.close();
    } on Object {
      // already closed
    }
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await outFuture;
    final stderr = await errFuture;
    if (!allowFailure && (timedOut || exit != 0)) {
      throw StateError('git ${args.join(' ')} failed ($exit): $stderr');
    }
    return GitRawResult(exitCode: exit, stdout: stdout, stderr: stderr);
  }

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final git = await _git;
    if (git == null) {
      throw StateError('git executable not found on PATH');
    }
    final process = await Process.start(
      git,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final dest = File(destPath);
    await dest.parent.create(recursive: true);
    final sink = dest.openWrite();
    final errFuture = process.stderr.transform(utf8.decoder).join();
    await process.stdout.pipe(sink);
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    final stderr = await errFuture;
    if (exit != 0) {
      if (await dest.exists()) await dest.delete();
      throw StateError('git ${args.join(' ')} failed ($exit): $stderr');
    }
  }

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async {
    if (Platform.isWindows) {
      throw UnsupportedError('runScript is POSIX-only');
    }
    final process = await Process.start(
      'sh',
      ['-c', script],
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final outFuture = process.stdout.transform(utf8.decoder).join();
    final errFuture = process.stderr.transform(utf8.decoder).join();
    if (stdinText != null) process.stdin.write(stdinText);
    try {
      await process.stdin.close();
    } on Object {
      // already closed
    }
    var timedOut = false;
    final exit = await process.exitCode.timeout(
      timeout ?? const Duration(seconds: 30),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await outFuture;
    final stderr = await errFuture;
    if (timedOut || exit != 0) {
      throw StateError('sh -c failed ($exit): $stderr');
    }
    return GitCommandResult(exitCode: exit, stdout: stdout, stderr: stderr);
  }

  // NOTE: use `sh -c`, not `sh -lc`. A login shell sources profiles that can
  // abort (dash + a broken profile.d exits 2) or pollute stdout; the exec
  // channel's PATH already finds git/find.

  @override
  Future<GitCapability> probe() async =>
      gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true));
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart
```
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/git/git_command_runner.dart client/test/services/git/git_command_runner_test.dart && git commit -m "feat(git): add raw/file/script/probe to GitCommandRunner (local)"
```

---

## Task 2: GitCommandRunner —— WSL / Remote 实现

**Files:**
- Modify: `client/lib/services/git/git_command_runner.dart`
- Modify: `client/lib/services/storage/remote_file_store.dart`
- Test: `client/test/services/git/git_command_runner_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `GitRawResult` / `GitCapability` / 方法签名。
- Produces: `RemoteFileStore.execShellWithStdin(String command, List<int> stdin)`；`RemoteGitCommandRunner` 可选 `startShell` / `execShellWithStdin` 注入。

- [ ] **Step 1: Write the failing test**

新增：

```dart
  group('RemoteGitCommandRunner raw/script/probe', () {
    test('runRaw uses argv-safe exec and returns bytes', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('abc');
        },
        execShellWithStdin: (cmd, stdin) async {
          commands.add('$cmd|${utf8.decode(stdin)}');
          return _sshOk('ok');
        },
      );
      final raw = await runner.runRaw(['--git-dir', '/r', 'show', 'HEAD:a']);
      expect(raw.exitCode, 0);
      expect(utf8.decode(raw.stdout), 'abc');
      final withStdin = await runner.runRaw(
        ['--git-dir', '/r', 'update-ref', '--stdin'],
        stdinText: 'update refs/x y\n',
      );
      expect(withStdin.stdout, isNotEmpty);
      expect(commands.last, contains('update refs/x y'));
    });

    test('runToFile redirects on the host', () async {
      final commands = <String>[];
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async {
          commands.add(cmd);
          return _sshOk('');
        },
      );
      await runner.runToFile(['--git-dir', '/r', 'show', 'HEAD:a'], '/tmp/x y');
      expect(commands.single, contains('>'));
      expect(commands.single, contains("'/tmp/x y'"));
    });

    test('probe parses version via runRaw', () async {
      final runner = RemoteGitCommandRunner(
        execShell: (cmd) async => _sshOk('git version 2.43.0'),
      );
      final cap = await runner.probe();
      expect(cap.available, isTrue);
      expect(cap.version, '2.43');
      expect(cap.pathspecFromFile, isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart --plain-name "RemoteGitCommandRunner raw"
```
Expected: 编译失败（缺 `execShellWithStdin` 参数与实现）。

- [ ] **Step 3: Write minimal implementation**

`RemoteFileStore` 新增：

```dart
  /// Runs [command] on the host with [stdin] bytes; returns the raw result.
  Future<SSHRunResult> execShellWithStdin(
    String command,
    List<int> stdin, {
    Duration timeout = SshStorageIo.provisionPhaseTimeout,
  }) {
    return _clientFactory.runOnStorageWithStdin(
      _profile,
      command,
      stdin: stdin,
      timeout: timeout,
    );
  }
```

`RemoteGitCommandRunner` 构造增加可选：
```dart
    Future<SSHRunResult> Function(String command, List<int> stdin)?
        execShellWithStdin,
```
字段 `_execShellWithStdin`；默认 `store?.execShellWithStdin`。

实现：
```dart
  @override
  Future<GitRawResult> runRaw(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    bool allowFailure = false,
    Duration? timeout,
  }) async {
    final command = HostShellArgv.command(
      executable: _git,
      arguments: args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final SSHRunResult result;
    if (stdinText == null) {
      result = await _execShell(command);
    } else {
      final exec = _execShellWithStdin;
      if (exec == null) throw StateError('stdin exec not configured');
      result = await exec(command, utf8.encode(stdinText));
    }
    final exit = result.exitCode ?? (sshRunSucceeded(result) ? 0 : 1);
    final raw = GitRawResult(
      exitCode: exit,
      stdout: result.stdout,
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
    if (!allowFailure && exit != 0) {
      throw StateError('git ${args.join(' ')} failed ($exit): ${raw.stderr}');
    }
    return raw;
  }

  @override
  Future<void> runToFile(
    List<String> args,
    String destPath, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final base = HostShellArgv.command(
      executable: _git,
      arguments: args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final result = await _execShell(
      '$base > ${RemoteFileStore.shellSingleQuote(destPath)}',
    );
    if (sshRunFailed(result)) {
      throw StateError('git ${args.join(' ')} redirect failed');
    }
  }

  @override
  Future<GitCommandResult> runScript(
    String script, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? stdinText,
    Duration? timeout,
  }) async {
    final prefix = HostShellArgv.command(
      executable: 'sh',
      arguments: ['-c', script],
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final result = stdinText == null
        ? await _execShell(prefix)
        : await _execShellWithStdin!(prefix, utf8.encode(stdinText));
    final out = GitCommandResult(
      exitCode: result.exitCode ?? (sshRunSucceeded(result) ? 0 : 1),
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
    // Same non-zero contract as LocalGitCommandRunner.runScript: silently
    // returning an empty stdout on a failed script would make Task 4's `find`
    // look like an empty runtime directory.
    if (out.exitCode != 0) {
      throw StateError('sh -c failed (${out.exitCode}): ${out.stderr}');
    }
    return out;
  }

  @override
  Future<GitCapability> probe() async =>
      gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true));
```

`WslGitCommandRunner` 用同样思路，基于 `wsl.exe`：
- `runRaw`：`Process.start('wsl.exe', HostWslArgv.processInvocation(...), ...)`，stdout 收集 bytes。
- `runToFile`：`sh -c '<git argv> > <quoted dest>'`。
- `runScript`：`wsl.exe sh -c script`。**必须与 Local / Remote 一样在非零退出或超时时抛 `StateError`**，不要返回带非零 exitCode 的结果（否则 Task 4 的 `find` 失败会被当成空目录）。
- `probe`：`gitCapabilityFromVersion(await runRaw(['--version'], allowFailure: true))`（与 Local/Remote 共用解析）。

> 实现 WSL 时复用 `HostWslArgv.processInvocation`（已有），不要手拼 `wsl.exe` 参数。

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart
```
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/git/git_command_runner.dart client/lib/services/storage/remote_file_store.dart client/test/services/git/git_command_runner_test.dart && git commit -m "feat(git): implement raw/file/script/probe for WSL and remote runners"
```

---

## Task 3: SeatRewindStore 去 dart:io（纯重构）

**Files:**
- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**
- Consumes: `GitCommandRunner`（Task 1/2）、`Filesystem`。
- Produces:
  ```dart
  SeatRewindStore({
    required String gitDir,
    required String workTree,
    required SeatRewindTarget target,
    GitCommandRunner? git,
    Filesystem? fs,
    String gitExecutable = 'git',
    Duration commandTimeout = const Duration(seconds: 30),
  });
  // Retained: existing production callers + the fake-git-script baseline test.
  // Task 6 switches them to forContext.
  factory SeatRewindStore.forSession({
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required SeatRewindTarget target,
    String gitExecutable = 'git',
    Duration commandTimeout = const Duration(seconds: 30),
  });
  factory SeatRewindStore.forContext({
    required RuntimeContext context,
    required String workspaceId,
    required String sessionId,
    required SeatRewindTarget target,
    String? gitExecutable,
    Duration commandTimeout = const Duration(seconds: 30),
  });
  ```
  默认 `git = LocalGitCommandRunner(gitExecutable: gitExecutable)`、`fs = LocalFilesystem()`，因此现有测试的 `SeatRewindStore(gitDir:…, workTree:…, target:…)` 不用改。

  **`gitExecutable` 与 `forSession` 必须保留**：`seat_rewind_store_test.dart:219` 用 `gitExecutable: scriptPath` 注入假 git 脚本，并且 `seat_rewind_policy.dart` / `seat_rewind_controller.dart` 仍调用 `forSession`。删掉会破坏「现有 513 行基线原样通过」这一更高优先级约束。Task 6 才把它们切到 `forContext`。

- [ ] **Step 1: Write the failing test**

在 `seat_rewind_store_test.dart` 末尾新增（证明注入生效）：

```dart
  test('store uses the injected GitCommandRunner and Filesystem', () async {
    final tmp = tmpDir.path;
    final runner = _RecordingGitRunner(LocalGitCommandRunner());
    final fs = _RecordingFs();
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
      git: runner,
      fs: fs,
    );
    await store.ensureRepo();
    expect(runner.calls, isNotEmpty);
    expect(fs.calls, isNotEmpty);
  });
```

并在文件底部新增（`repoExists()` 是纯 fs 操作，不能用来断言 git 注入，所以用 `ensureRepo()`；同时注入一个记录调用的 `Filesystem` 来真正验证 fs 接线）：

```dart
final class _RecordingFs extends LocalFilesystem {
  final calls = <String>[];

  @override
  Future<FsStat> stat(String path) async {
    calls.add(path);
    return super.stat(path);
  }
}
```

以及：

```dart
final class _RecordingGitRunner implements GitCommandRunner {
  _RecordingGitRunner(this._inner);
  final GitCommandRunner _inner;
  final calls = <List<String>>[];

  @override
  Future<bool> get isAvailable => _inner.isAvailable;

  @override
  Future<GitCommandResult> runInDirectory(String dir, List<String> args, {Map<String, String>? environment}) =>
      _inner.runInDirectory(dir, args, environment: environment);

  @override
  Future<GitRawResult> runRaw(List<String> args, {String? workingDirectory, Map<String, String>? environment, String? stdinText, bool allowFailure = false, Duration? timeout}) {
    calls.add(args);
    return _inner.runRaw(args, workingDirectory: workingDirectory, environment: environment, stdinText: stdinText, allowFailure: allowFailure, timeout: timeout);
  }

  @override
  Future<void> runToFile(List<String> args, String destPath, {String? workingDirectory, Map<String, String>? environment, Duration? timeout}) {
    calls.add(args);
    return _inner.runToFile(args, destPath, workingDirectory: workingDirectory, environment: environment, timeout: timeout);
  }

  @override
  Future<GitCommandResult> runScript(String script, {String? workingDirectory, Map<String, String>? environment, String? stdinText, Duration? timeout}) =>
      _inner.runScript(script, workingDirectory: workingDirectory, environment: environment, stdinText: stdinText, timeout: timeout);

  @override
  Future<GitCapability> probe() => _inner.probe();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart --plain-name "injected"
```
Expected: 编译失败（`SeatRewindStore` 无 `git:` / `fs:` 参数）。

- [ ] **Step 3: Write minimal implementation**

按以下映射把 `seat_rewind_store.dart` 的 `dart:io` 全部替换（逐条）：

| 原调用 | 替换 |
|---|---|
| `Directory(gitDir).exists()` / `existsSync()` | `(await fs.stat(gitDir)).exists` |
| `File(p.join(gitDir,'HEAD')).exists()` | `(await fs.stat(paths.join(gitDir,'HEAD'))).exists` |
| `Directory(gitDir).create(recursive:true)` | `await fs.ensureDir(gitDir)` |
| `File(exclude).writeAsString(...)` | `await fs.writeString(excludePath, ...)` |
| `File(indexFile).existsSync()` / `deleteSync()` | `(await fs.stat(indexFile)).exists` / `await fs.removeRecursive(indexFile)` |
| `File(p.join(workTree, relative)).delete()` | `await fs.removeRecursive(paths.join(workTree, relative))` |
| `FileSystemEntity.type(path, followLinks:false)` | `(await fs.lstat(path)).kind`（`FsEntityKind`） |
| `Directory(root).list(followLinks:false)` | `await fs.listDir(path)` + 对每项 `await fs.lstat(childPath)` |
| `FileSystemEntity.isLink(path)` | `(await fs.lstat(path)).isSymlink` |
| `Link(path).delete()` | `await fs.removeRecursive(path)` |
| `dest.parent.create(recursive:true)` | `await fs.ensureDir(paths.dirname(destPath))` |
| `dest.openWrite()` + `_runGitToFile` | `await git.runToFile(args, destPath)` |
| `_runProcess` / `_runGit` / `_runGitResult` | `git.runRaw(args, workingDirectory:…, environment:…, stdinText:…, allowFailure:…, timeout: commandTimeout)` |
| `Uri.file(sourceGitDir).toString()` | `paths.style == p.Style.posix ? sourceGitDir : Uri.file(sourceGitDir).toString()` |

构造函数与工厂：

```dart
  SeatRewindStore({
    required this.gitDir,
    required this.workTree,
    required this.target,
    GitCommandRunner? git,
    Filesystem? fs,
    this.commandTimeout = const Duration(seconds: 30),
  }) : git = git ?? LocalGitCommandRunner(),
       fs = fs ?? LocalFilesystem();

  final GitCommandRunner git;
  final Filesystem fs;
  p.Context get paths => fs.pathContext;

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
      'rewind',
      target.seatKey,
    ),
    workTree: context.layout.workspace.sessionRuntimeDir(workspaceId, sessionId),
    target: target,
    git: gitCommandRunnerForContext(context, gitExecutable: gitExecutable),
    fs: context.filesystem,
    commandTimeout: commandTimeout,
  );
```

`showFile` 改为：

```dart
  Future<String?> showFile(String commit, String path) async {
    final result = await git.runRaw(
      [..._repoArgs, 'show', '$commit:$path'],
      workingDirectory: workTree,
      allowFailure: true,
      timeout: commandTimeout,
    );
    if (result.exitCode == 0) return _utf8OrNull(result.stdout);
    if (target.seatKey != 'personal') return null;
    final sourcePath = await _personalizedSourcePath(commit, path);
    if (sourcePath == null) return null;
    final mapped = await git.runRaw(
      [..._repoArgs, 'show', '$commit:$sourcePath'],
      workingDirectory: workTree,
      allowFailure: true,
      timeout: commandTimeout,
    );
    if (mapped.exitCode != 0) return null;
    return _utf8OrNull(mapped.stdout);
  }
```

`runRaw(allowFailure: true)` 在 git 失败/超时时返回非零 `exitCode` 而不抛异常，所以这里**不要** `try/catch`，更不要用 `on Object` 吞掉 `TypeError` / `NoSuchMethodError` 等编程错误。

同理 `_includedRuntimeFiles` 里 `Directory.list` 的 `on FileSystemException` 换成 `fs.listDir` 后若必须用 `on Object` 才能去掉 `dart:io`，则必须重新抛出编程错误并让日志如实描述：

```dart
      } on Object catch (error) {
        if (error is TypeError ||
            error is NoSuchMethodError ||
            error is ArgumentError) {
          rethrow;
        }
        AppLogger.instance.w('[rewind] skipped runtime directory $dirPath: $error');
        return;
      }
```

删除 `dart:io` import；保留 `p` import（路径拼接）。

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart test/services/chat/rewind/seat_branches_test.dart
```
Expected: 全部 PASS（现有 513 行用例行为不变）。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/chat/rewind/seat_rewind_store.dart client/test/services/chat/rewind/seat_rewind_store_test.dart && git commit -m "refactor(rewind): route SeatRewindStore through GitCommandRunner and Filesystem"
```

---

## Task 4: 远端 O(N) 优化（find / skip stale）

**Files:**
- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_store_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `git` / `fs` / `paths`。
- Produces: `bool get isRemote => fs.isRemote;`（store 内部）。

- [ ] **Step 1: Write the failing test**

新增（用真实的本地 fs/git，但把 `isRemote` 覆盖为 true，从而走远端分支；Windows 跳过）：

```dart
  test('remote store lists included files with one find and skips stale check', () async {
    if (Platform.isWindows) return; // runScript is POSIX-only
    final tmp = tmpDir.path;
    final runner = _RecordingGitRunner(LocalGitCommandRunner());
    final store = SeatRewindStore(
      gitDir: '$tmp/repo.git',
      workTree: '$tmp/work',
      target: const SeatRewindTarget(
        kind: SeatRewindKind.personalAcp,
        tool: 'claude',
      ),
      git: runner,
      fs: _RemoteDelegatingFs(),
    );
    expect(store.isRemote, isTrue);
    await store.commitTurn(messageId: 'm1');
    expect(runner.scripts.where((s) => s.contains('find')), hasLength(1));
    expect(runner.calls.any((c) => c.contains('ls-files')), isFalse);
  });
```

文件底部：

```dart
final class _RemoteDelegatingFs extends LocalFilesystem {
  @override
  bool get isRemote => true;
}
```

`_RecordingGitRunner` 增加 `final scripts = <String>[];`，在 `runScript` 里 `scripts.add(script);`。

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart --plain-name "remote store lists"
```
Expected: FAIL（当前 `_includedRuntimeFiles` 走 `Directory.list`，`ls-files` 仍被调用）。

- [ ] **Step 3: Write minimal implementation**

在 `SeatRewindStore` 加：

```dart
  bool get isRemote => fs.isRemote;
```

`_includedRuntimeFiles`：

```dart
  Future<List<String>> _includedRuntimeFiles() async {
    if (isRemote) {
      final excludes = rewindExcludeNames
          .map(
            (name) => '-not -path '
                '${RemoteFileStore.shellSingleQuote('*/$name/*')} ',
          )
          .join();
      final result = await git.runScript(
        'find . -type f $excludes-print',
        workingDirectory: workTree,
      );
      return [
        for (final line in const LineSplitter().convert(result.stdout))
          if (line.trim().isNotEmpty)
            line.trim().replaceFirst(RegExp(r'^\./'), ''),
      ].where((p) => target.includes(p) && !target.isExcluded(p)).toList();
    }
    // 本地分支：保留 Task 3 的 fs.listDir 递归实现，不要改。
  }
```

> `seat_rewind_store.dart` 需要新增 import：`dart:convert`（`LineSplitter`）与 `../../storage/remote_file_store.dart`（`RemoteFileStore.shellSingleQuote`）。

`_dropStaleSeatIndexEntries` 开头加：

```dart
    if (isRemote) return; // remote: avoid N round-trips; git add covers deletions
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_store_test.dart
```
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/chat/rewind/seat_rewind_store.dart client/test/services/chat/rewind/seat_rewind_store_test.dart && git commit -m "perf(rewind): batch remote file listing and skip stale index walk"
```

- [x] **Step 6 (follow-up): Batch the remote `commitTurn` sequence**

Step 3 above only removed the two O(N) listings; a remote turn still issued
`add → write-tree → rev-parse parent → commit-tree → 3× update-ref` as ~8
sequential execs. `_commitTurnRemoteBatched` now folds that whole sequence
(plus parent/root resolution) into one `runScript`, so a steady-state remote
turn is `find` + one script (2 execs). Older git without
`--pathspec-from-file` falls back to the per-step path. Test:
`remote commitTurn batches add/write-tree/commit-tree/update-ref into one script`.

---

## Task 5: SeatRuntimeResolver + RewindCapability

**Files:**
- Create: `client/lib/services/chat/rewind/seat_runtime_resolver.dart`
- Create: `client/lib/services/chat/rewind/rewind_capability.dart`
- Test: `client/test/services/chat/rewind/seat_runtime_resolver_test.dart`
- Test: `client/test/services/chat/rewind/rewind_capability_test.dart`

**Interfaces:**
- Produces:
  ```dart
  final class SeatRuntimeResolver {
    SeatRuntimeResolver({required Future<RuntimeContext> Function(RuntimeTarget) resolve});
    Future<RuntimeContext> forTarget(RuntimeTarget target);
    RuntimeContext? peek(String targetId); // 同步读已解析缓存
    void invalidate(String targetId);
    void clear(); // home 切换 / 重连
  }

  final class RewindCapability {
    const RewindCapability({required this.available, this.version, this.pathspecFromFile = false});
    final bool available;
    final String? version;
    final bool pathspecFromFile;
    static const unavailable = RewindCapability(available: false);
  }

  final class RewindCapabilityCache {
    RewindCapabilityCache({required GitCommandRunner Function(RuntimeContext) runnerFor});
    Future<RewindCapability> forContext(RuntimeContext ctx);
    RewindCapability? peek(String targetId); // 同步读已探测缓存
    void invalidate(String targetId);
    void clear(); // home 切换 / 重连
  }
  ```

- [ ] **Step 1: Write the failing tests**

`seat_runtime_resolver_test.dart`：

```dart
test('caches by target id and invalidates', () async {
  var calls = 0;
  final resolver = SeatRuntimeResolver(
    resolve: (target) async {
      calls++;
      return _ctx(target);
    },
  );
  const target = RuntimeTarget(id: 'ssh:p', label: 'p', kind: RuntimeKind.ssh);
  await resolver.forTarget(target);
  await resolver.forTarget(target);
  expect(calls, 1);
  resolver.invalidate(target.id);
  await resolver.forTarget(target);
  expect(calls, 2);
});
```

`rewind_capability_test.dart`：`available` / `version` / `pathspecFromFile` 透传 + 缓存 + 失效。

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_runtime_resolver_test.dart test/services/chat/rewind/rewind_capability_test.dart
```
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: Implement**

`seat_runtime_resolver.dart`：

```dart
import '../../../models/runtime_target.dart';
import '../../storage/runtime_context.dart';

final class SeatRuntimeResolver {
  SeatRuntimeResolver({
    required Future<RuntimeContext> Function(RuntimeTarget target) resolve,
  }) : _resolve = resolve;

  final Future<RuntimeContext> Function(RuntimeTarget target) _resolve;
  final _cache = <String, Future<RuntimeContext>>{};

  final _values = <String, RuntimeContext>{};

  Future<RuntimeContext> forTarget(RuntimeTarget target) {
    final existing = _cache[target.id];
    if (existing != null) return existing;
    final future = _resolve(target).then((ctx) {
      _values[target.id] = ctx;
      return ctx;
    });
    _cache[target.id] = future;
    return future;
  }

  RuntimeContext? peek(String targetId) => _values[targetId];

  void invalidate(String targetId) {
    _cache.remove(targetId);
    _values.remove(targetId);
  }

  void clear() {
    _cache.clear();
    _values.clear();
  }
}
```

`rewind_capability.dart`：

```dart
import '../../git/git_command_runner.dart';
import '../../storage/runtime_context.dart';

final class RewindCapability {
  const RewindCapability({
    required this.available,
    this.version,
    this.pathspecFromFile = false,
  });
  final bool available;
  final String? version;
  final bool pathspecFromFile;
  static const unavailable = RewindCapability(available: false);
}

final class RewindCapabilityCache {
  RewindCapabilityCache({
    required GitCommandRunner Function(RuntimeContext) runnerFor,
  }) : _runnerFor = runnerFor;

  final GitCommandRunner Function(RuntimeContext) _runnerFor;
  final _cache = <String, Future<RewindCapability>>{};
  final _values = <String, RewindCapability>{};

  Future<RewindCapability> forContext(RuntimeContext ctx) {
    final existing = _cache[ctx.target.id];
    if (existing != null) return existing;
    final future = _probe(ctx).then((cap) {
      _values[ctx.target.id] = cap;
      return cap;
    });
    _cache[ctx.target.id] = future;
    return future;
  }

  RewindCapability? peek(String targetId) => _values[targetId];

  Future<RewindCapability> _probe(RuntimeContext ctx) async {
    final cap = await _runnerFor(ctx).probe();
    return RewindCapability(
      available: cap.available,
      version: cap.version,
      pathspecFromFile: cap.pathspecFromFile,
    );
  }

  void invalidate(String targetId) {
    _cache.remove(targetId);
    _values.remove(targetId);
  }

  void clear() {
    _cache.clear();
    _values.clear();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_runtime_resolver_test.dart test/services/chat/rewind/rewind_capability_test.dart
```
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/chat/rewind/seat_runtime_resolver.dart client/lib/services/chat/rewind/rewind_capability.dart client/test/services/chat/rewind/seat_runtime_resolver_test.dart client/test/services/chat/rewind/rewind_capability_test.dart && git commit -m "feat(rewind): add work-plane resolver and git capability cache"
```

---

## Task 6: Policy / Fork / Cubit 接线

**Files:**
- Modify: `client/lib/services/chat/rewind/seat_rewind_policy.dart`
- Modify: `client/lib/services/chat/rewind/rewind_fork_service.dart`
- Modify: `client/lib/services/chat/rewind/seat_rewind_controller.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_policy_test.dart`

**Interfaces:**
- Consumes: `SeatRuntimeResolver`、`RewindCapabilityCache`、`SeatRewindStore.forContext`。
- Produces:
  ```dart
  final class SeatRewindPolicy {
    SeatRewindPolicy({
      required RuntimeTarget Function(AppSession session, String? memberId) workTargetFor,
      required RuntimeContext? Function(RuntimeTarget target) contextFor,
      required RewindCapability Function(RuntimeTarget target) capabilityFor,
    });
  }
  ```
  `RewindDenial` 改为 `{mixedSeatsDisabled, workPlaneNotReady, gitMissing, unsupportedBackend}`。

- [ ] **Step 1: Write the failing test**

`seat_rewind_policy_test.dart` 改为：

```dart
test('local + git available is allowed', () async { ... });
test('remote ssh + git available is allowed', () async { ... });
test('no git -> gitMissing', () async { ... });
test('unresolved work context -> workPlaneNotReady', () async { ... });
test('windows remote -> unsupportedBackend', () async { ... });
// 删除 mobilePlatform / remoteRuntime 断言
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_policy_test.dart
```
Expected: FAIL（旧 denial 与新签名）。

- [ ] **Step 3: Implement**

`SeatRewindPolicy.evaluate` 改为同步读缓存：

```dart
  SeatRewindEligibility evaluate({
    required AppSession session,
    required String? memberId,
    required CliTool cli,
    required bool acp,
    bool allowMixed = false,
  }) {
    if (!allowMixed && !session.isSimple && !kMixedSeatRewindEnabled) {
      return const SeatRewindEligibility.denied(RewindDenial.mixedSeatsDisabled);
    }
    final target = workTargetFor(session, memberId);
    final ctx = contextFor(target);
    if (ctx == null) {
      return const SeatRewindEligibility.denied(RewindDenial.workPlaneNotReady);
    }
    if (target.kind == RuntimeKind.ssh && target.remoteOs == RemoteOs.windows) {
      return const SeatRewindEligibility.denied(RewindDenial.unsupportedBackend);
    }
    final cap = capabilityFor(target);
    if (!cap.available) {
      return const SeatRewindEligibility.denied(RewindDenial.gitMissing);
    }
    return SeatRewindEligibility.ready(
      SeatRewindStore.forContext(
        context: ctx,
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        target: resolveSeatRewindTarget(
          personal: session.isSimple,
          acp: acp,
          tool: cli.value,
          memberId: memberId,
        ),
      ),
    );
  }
```

`SeatRewindPolicy` 构造改为接收 `RuntimeContext? Function(AppSession, String?)`（同步读已解析缓存）与 `RewindCapability Function(String targetId)`。`SessionHistoryRewindHost._reload` 负责先 `await resolver.forTarget` + `await capability.forContext`，再 `evaluate`。

`rewind_fork_service.dart` 删除：

```dart
    if (!seat.localRuntime) {
      throw StateError('Cannot rewind a remote runtime');
    }
```

`SeatRewindController._eligibility` 与 `loadBranches/fork` 改用 `SeatRewindStore.forContext`。

`ChatCubit` 构造：

```dart
  late final SeatRuntimeResolver _seatRuntimeResolver = SeatRuntimeResolver(
    resolve: (target) => _lifecycle.resolveWorkContextForTargetId(target.id),
  );

  late final RewindCapabilityCache _rewindCapability = RewindCapabilityCache(
    runnerFor: (ctx) => gitCommandRunnerForContext(
      ctx,
      gitExecutable: configuredGitExecutable?.call(),
    ),
  );

  RuntimeTarget _workTargetForRewind(AppSession session, String? memberId) =>
      _lifecycle.launchWorkTarget(
        _launchService.launchContextFor(session),
        memberId: session.isSimple ? null : memberId,
      );

  late final SeatRewindPolicy _rewindPolicy = SeatRewindPolicy(
    workTargetFor: _workTargetForRewind,
    contextFor: (target) => _seatRuntimeResolver.peek(target.id),
    capabilityFor: (target) =>
        _rewindCapability.peek(target.id) ?? RewindCapability.unavailable,
  );

  /// Pre-resolves the work context + git capability so the synchronous policy
  /// can read them. Call from the rewind host before `rewindActionsAllowed`.
  Future<void> prepareRewindFor(AppSession session, String memberId) async {
    final target = _workTargetForRewind(session, memberId);
    final ctx = await _seatRuntimeResolver.forTarget(target);
    await _rewindCapability.forContext(ctx);
  }
```

`SessionHistoryRewindHost._reload` 在 `rewindActionsAllowed` 之前加一行：

```dart
    await cubit.prepareRewindFor(widget.session, widget.memberId);
    final allowed = cubit.rewindActionsAllowed(widget.session, widget.memberId);
```

home 切换 / 重连时清空缓存（在现有 home generation / storage swap 回调里）：

```dart
    _seatRuntimeResolver.clear();
    _rewindCapability.clear();
```

> `peek` 是同步读缓存；`evaluate` 在缓存未就绪时返回 `workPlaneNotReady`，`_reload` 会在 `prepareRewindFor` 完成后重试。

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_policy_test.dart test/services/chat/rewind/rewind_fork_service_test.dart test/services/chat/rewind/seat_branches_test.dart
```
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/services/chat/rewind/seat_rewind_policy.dart client/lib/services/chat/rewind/rewind_fork_service.dart client/lib/services/chat/rewind/seat_rewind_controller.dart client/lib/cubits/chat_cubit.dart client/test/services/chat/rewind/seat_rewind_policy_test.dart && git commit -m "feat(rewind): capability-driven policy over work-plane contexts"
```

---

## Task 7: 移动端放开 + 收尾修复 + 全量验证

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/pages/chat/session_history_rewind_host.dart`
- Modify: `client/lib/services/chat/rewind/seat_rewind_store.dart`
- Modify: `client/lib/services/cli/git_on_path.dart`
- Test: `client/test/services/chat/rewind/seat_rewind_policy_test.dart`
- Manual: Android 真机

**Interfaces:**
- Consumes: Task 6 的 capability policy、Task 5 `SeatRuntimeResolver`/`RewindCapabilityCache`、Task 3 `SeatRewindStore.forContext`。

> Task 6 已把 `isMobile` / `RewindDenial.mobilePlatform` / `RewindDenial.remoteRuntime` 全部删除（全仓 grep 为空），所以原「删除 mobile 拒绝」这一步已完成。本任务 Step 3 改为 Task 6 遗留的三项修复（详见 ledger）。

- [ ] **Step 1: Write the failing test**

在 `seat_rewind_policy_test.dart` 新增一个真实回归测试，沿用该文件现有的 `policy(...)` 与 `session()` helper：

```dart
test('ssh work plane with git is eligible (mobile enablement)', () {
  final result = policy(
    target: const RuntimeTarget(
      id: 'ssh:phone',
      label: 'Phone',
      kind: RuntimeKind.ssh,
    ),
    capability: const RewindCapability(
      available: true,
      version: '2.43',
      pathspecFromFile: true,
    ),
  ).evaluate(
    session: session(),
    memberId: null,
    cli: CliTool.claude,
    acp: false,
  );
  expect(result.allowed, isTrue);
});
```

`policy(...)` helper 的 `contextFor` 必须对该 ssh target 返回一个 `RuntimeContext`（用 Task 5 测试里的 `ctx(target, dir)` 形状构造；`RuntimeTarget.id` 要与传入的一致）。若 helper 已有 `capability` 参数则复用，否则补上。

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/services/chat/rewind/seat_rewind_policy_test.dart --plain-name "ssh work plane"
```
Expected: FAIL 或编译失败（helper 尚不支持 ssh context / capability 注入）；记录真实 RED 输出。

- [ ] **Step 3: Implement the three Task 6 carry-over fixes + mobile cleanup**

1. **Home-swap cache eviction（M1，真实的错平面风险）。** `HomeStorage.changes` 是 public broadcast stream（`home_storage.dart:64`），`ChatCubit` 持有 `_storage`。在 `ChatCubit` 里订阅并在 `close()` 中取消：
   ```dart
   late final StreamSubscription<StoragePlaneChange> _rewindPlaneSub =
       _storage.changes.listen((_) => clearRewindCaches());
   ```
   `close()` 里加 `await _rewindPlaneSub.cancel();`（若已有 `close()` 只加这一行）。备选更省的做法：在 `prepareRewindFor` 里比对已缓存 context 的 `appDataRoot` 与当前 `_storage.context.appDataRoot`，不同则 invalidate 两个缓存。**二选一，不要都做。**
2. **`_reload` guard（M2）。** `session_history_rewind_host.dart` 的 `_reload()` 是 fire-and-forget；给 `await cubit.prepareRewindFor(...)` 包 try/catch，失败时记日志并让 `allowed=false` 分支继续（保留 `mounted` / `serial` 检查），避免 unhandled zone error 与跳过 `setState`。
3. **删除 dead `SeatRewindStore.forSession`（M3）。** 先 `grep -rn "SeatRewindStore.forSession" client` 确认为空；若仍有调用者，先迁到 `forContext` 再删。删掉后路径规则只剩 `forContext` 一份。
4. `git_on_path.dart`：`grep -rn "isMobilePlatform" client` 若为空则删除该函数（保留 `gitOnPath()`，R2 的本地回退仍用）；非空则保留。

> 不要再改 `SeatRewindPolicy` 的 denial 枚举或删 `isMobile` —— Task 6 已完成。

- [ ] **Step 4: Run focused + full verification**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/services/chat/rewind/ test/services/git/git_command_runner_test.dart
```
Expected: 0 errors；测试全绿。

Then once, in background:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart
```
Expected: 全绿（若出现 `Failed to load` transport 错误，按既有环境 flake 处理，不重复全量）。

- [ ] **Step 5: Device checklist (manual, deferred to the human)**

在 Android 上确认：
1. 长按用户消息 → 菜单出现「编辑 / 从此 fork / 上一版 / 下一版」（此前只有复制/导出/重试）。
2. 点击用户气泡 → 底部面板、其余消息压暗、键盘弹起时面板在键盘上方。
3. 发送后面板关闭、旧轮次被替换、遮罩复原。
4. 版本 `1/2` 可切换，切换后 transcript 增长/缩短。
5. 桌面端（本地 home）行为与改动前一致。

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add <只列出本次实际修改的文件> && git commit -m "feat(rewind): enable mobile rewind and close work-plane cache lifecycle"
```

---

## Self-Review（对照 spec）

**1. Spec coverage**

| Spec 要求 | 任务 |
|---|---|
| work-plane context 作为 store 来源 | Task 3 `forContext`、Task 6 policy |
| 复用 `GitCommandRunner` + `Filesystem` | Task 1/2/3 |
| `runRaw/runToFile/runScript/probe` | Task 1/2 |
| 远端 O(N) 批处理 | Task 4 |
| `SeatRuntimeResolver` / `RewindCapability` | Task 5 |
| capability 驱动 policy，删 mobile/remote 拒绝 | Task 6/7 |
| 删 `!seat.localRuntime` | Task 6 |
| WSL 顺带支持 | Task 2 |
| Windows 远端拒绝 | Task 6 `unsupportedBackend` |
| 本地行为不变 | Task 3 现有测试全绿 |
| UI 不改 | 无任务（已就绪） |
| 测试与验证 | 各任务 + Task 7 |

无遗漏。

**2. Placeholder scan** — 唯一需要实现者判断的是 Task 4 `_includedRuntimeFiles` 的两段示例；计划已明确「只保留 `single` 那份」，不是占位符。

**3. Type consistency** — `GitRawResult` / `GitCapability` / `runRaw` / `runToFile` / `runScript` / `probe` 在 Task 1 定义，Task 2-7 一致使用；`SeatRewindStore.forContext` 在 Task 3 定义，Task 6 使用；`RewindCapability` 在 Task 5 定义，Task 6/7 使用。

---

## Execution Handoff

计划已保存。两种执行方式：

1. **Subagent-Driven（推荐）** — 每个任务派新 subagent，任务间两阶段 review。
2. **Inline Execution** — 当前会话按 `executing-plans` 分批执行，带检查点。

选哪个？
