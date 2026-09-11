# Auto Git Fetch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Periodically run `git fetch --all --prune` (non-interactive, 60s timeout) for the repository the source-control panel currently shows, so ahead/behind counts stay fresh.

**Architecture:** A pure-Dart `GitAutoFetchScheduler` owns timing and in-flight coalescing; `RightToolsLifecycleHost` drives it through its existing suspend/resume gating signals and refreshes status + graph cubits after each fetch. A new `fetchAllQuiet` git action passes `GIT_TERMINAL_PROMPT=0` through a new optional `environment` parameter on `GitCommandRunner.runInDirectory`. Toggle + interval live in `SessionPreferences` with UI in the session config section.

**Tech Stack:** Flutter/Dart, flutter_bloc, existing `GitCommandRunner`/`HostOneShotRunner` stack, `fake_async` for timer tests.

**Spec:** `docs/superpowers/specs/2026-09-09-auto-git-fetch-design.md`

## Global Constraints

- Never invoke `flutter test` directly — always `cd client && dart run tool/run_tests.dart <paths>`. Narrow with `--plain-name "<test name>"`.
- Inner test loop: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`; one test file for verification; full suite only once before claiming done (Task 7).
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then regenerate with `cd client && flutter gen-l10n`.
- Logging: diagnostics → `AppLogger` (`appLogger`); no `print`.
- All new comments in this codebase's style: Chinese for service doc-comments where neighboring code uses Chinese (see `git_history_actions.dart`), English where the file is English (see `right_tools_lifecycle.dart`).
- Commits: conventional-commit style (`feat:`/`test:`/`refactor:`), end message body with `Co-Authored-By: Claude <noreply@anthropic.com>`.

---

### Task 1: `environment` passthrough in `GitCommandRunner`

**Files:**
- Modify: `client/lib/services/cli/cli_tool_locator.dart:12-30` (`ProcessRunner` typedef + `cliToolDefaultProcessRun`)
- Modify: `client/lib/services/git/git_command_runner.dart` (interface + 3 runner classes + `_hostProcessRunnerFrom`)
- Test: `client/test/services/git/git_command_runner_test.dart`

**Interfaces:**
- Produces: `Future<GitCommandResult> runInDirectory(String dir, List<String> args, {Map<String, String>? environment})` — used by Task 2. All existing callers (positional args only) keep compiling; `TestGitCommandRunner` (test support, fewer named params) stays a valid override.

- [ ] **Step 1: Write the failing tests**

Append this group inside `main()` of `client/test/services/git/git_command_runner_test.dart` (imports for `HostOneShotRunner`, `HostRunRequest`, `HostRunResult` are already at the top of that file):

```dart
class _RecordingHostRunner implements HostOneShotRunner {
  final List<HostRunRequest> requests = [];

  @override
  Future<HostRunResult> run(HostRunRequest request) async {
    requests.add(request);
    return const HostRunResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  // ... existing groups ...

  group('runInDirectory environment passthrough', () {
    test('LocalGitCommandRunner forwards environment via injected runner',
        () async {
      Map<String, String>? seenEnv;
      final runner = LocalGitCommandRunner(
        gitExecutable: '/usr/bin/git',
        runner: (
          String executable,
          List<String> arguments, {
          Map<String, String>? environment,
          Encoding? stdoutEncoding,
          Encoding? stderrEncoding,
        }) async {
          seenEnv = environment;
          return ProcessResult(0, 0, '', '');
        },
      );
      await runner.runInDirectory('/repo', ['status'], environment: {
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(seenEnv, {'GIT_TERMINAL_PROMPT': '0'});
      await runner.runInDirectory('/repo', ['status']);
      expect(seenEnv, isNull);
    });

    test('Wsl/Remote runners pass environment into HostRunRequest',
        () async {
      final host = _RecordingHostRunner();
      final wsl = WslGitCommandRunner(
        gitExecutable: '/usr/bin/git',
        hostRunner: host,
      );
      await wsl.runInDirectory('/repo', ['status'], environment: {
        'GIT_TERMINAL_PROMPT': '0',
      });
      final remote = RemoteGitCommandRunner(
        execShell: (cmd) async => _sshOk(''),
        hostRunner: host,
      );
      await remote.runInDirectory('/repo', ['status'], environment: {
        'GIT_TERMINAL_PROMPT': '0',
      });
      expect(
        host.requests.map((r) => r.environment),
        everyElement({'GIT_TERMINAL_PROMPT': '0'}),
      );
    });
  });
}
```

Note: `_RecordingHostRunner` and the group go inside the existing `main()`; `_sshOk` already exists at the top of this test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart`
Expected: COMPILE ERROR — `runInDirectory` has no named parameter `environment` (and the Local fake's closure doesn't match `ProcessRunner` yet because the closure uses `environment`, which the typedef lacks).

- [ ] **Step 3: Implement**

In `client/lib/services/cli/cli_tool_locator.dart`, extend the typedef and default runner so the environment survives the `ProcessRunner` hop (Dart function subtyping means existing fakes with fewer named params stay assignable):

```dart
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

Future<ProcessResult> cliToolDefaultProcessRun(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    environment: environment,
    stdoutEncoding: stdoutEncoding ?? systemEncoding,
    stderrEncoding: stderrEncoding ?? systemEncoding,
  );
}
```

In `client/lib/services/git/git_command_runner.dart`:

1. Interface (line ~34):

```dart
abstract interface class GitCommandRunner {
  Future<bool> get isAvailable;

  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  });
}
```

2. `_hostProcessRunnerFrom` (line ~51) — forward `environment` (this is the production path for `LocalGitCommandRunner`'s default host runner; dropping it here would silently discard the env):

```dart
    return runner(
      executable,
      arguments,
      environment: environment,
      stdoutEncoding: stdoutEncoding ?? const Utf8Codec(allowMalformed: true),
      stderrEncoding: stderrEncoding ?? const Utf8Codec(allowMalformed: true),
    );
```

3. Each of the three `runInDirectory` implementations gains the named parameter and passes it into its `HostRunRequest`, e.g. for `LocalGitCommandRunner`:

```dart
  @override
  Future<GitCommandResult> runInDirectory(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final git = await _git;
    if (git == null) {
      return const GitCommandResult(
        exitCode: 127,
        stdout: '',
        stderr: 'git executable not found on PATH',
      );
    }
    final result = await _host.run(
      HostRunRequest(
        executable: git,
        arguments: _gitArgv(dir, args),
        environment: environment,
      ),
    );
    return _gitResultFromHost(result);
  }
```

Apply the same signature change + `environment: environment` in `WslGitCommandRunner.runInDirectory` and `RemoteGitCommandRunner.runInDirectory`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_command_runner_test.dart`
Expected: PASS (all groups, including pre-existing ones — the change must not regress them).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/cli_tool_locator.dart client/lib/services/git/git_command_runner.dart client/test/services/git/git_command_runner_test.dart
git commit -m "feat(git): optional environment passthrough in GitCommandRunner

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `GitHistoryActions.fetchAllQuiet`

**Files:**
- Modify: `client/lib/services/git/git_history_actions.dart`
- Test: `client/test/services/git/git_history_actions_test.dart`

**Interfaces:**
- Consumes: `runInDirectory(dir, args, {environment})` from Task 1.
- Produces: `Future<void> fetchAllQuiet(String dir)` — fetches with `GIT_TERMINAL_PROMPT=0`. Used by Task 3/6. Throwing behavior identical to `fetchAll` (`GitException` on non-zero exit).

- [ ] **Step 1: Write the failing tests**

In `client/test/services/git/git_history_actions_test.dart`, extend `_FakeRunner` to record environments (the typedef gained `environment` in Task 1, so add the named param), then add tests:

```dart
class _FakeRunner {
  _FakeRunner(this.responses);
  final Map<String, ProcessResult> responses;
  final List<List<String>> calls = [];
  final List<Map<String, String>?> environments = [];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    final cIdx = arguments.indexOf('-C');
    if (cIdx < 0) return ProcessResult(0, 0, '/usr/bin/git\n', '');
    final cmd = arguments.sublist(cIdx + 2);
    calls.add(cmd);
    environments.add(environment);
    for (final e in responses.entries) {
      if (cmd.join(' ').startsWith(e.key)) return e.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}
```

```dart
  test('fetchAll runs the documented argv without environment', () async {
    await actions.fetchAll('/r');
    expect(fake.calls.single, ['fetch', '--all', '--prune']);
    expect(fake.environments.single, isNull);
  });

  test('fetchAllQuiet disables terminal prompting', () async {
    await actions.fetchAllQuiet('/r');
    expect(fake.calls.single, ['fetch', '--all', '--prune']);
    expect(fake.environments.single, {'GIT_TERMINAL_PROMPT': '0'});
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_history_actions_test.dart`
Expected: FAIL — `fetchAllQuiet` is not defined.

- [ ] **Step 3: Implement**

In `client/lib/services/git/git_history_actions.dart`, give `_run` an optional environment and add the quiet variant (place it right after `fetchAll`, matching the file's Chinese doc-comment style):

```dart
  Future<void> _run(
    String dir,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final result = await _runner.runInDirectory(
      dir,
      args,
      environment: environment,
    );
    if (result.exitCode != 0) {
      final detail = result.stderr.trim().isEmpty
          ? result.stdout.trim()
          : result.stderr.trim();
      appLogger.d(
        '[GitActions] ${args.join(' ')} exit ${result.exitCode}: $detail',
      );
      throw GitException(detail.isEmpty ? 'git ${args.first} failed' : detail);
    }
  }
```

```dart
  Future<void> fetchAll(String dir) => _run(dir, ['fetch', '--all', '--prune']);

  /// 非交互 fetch（自动刷新用）：`GIT_TERMINAL_PROMPT=0` 让缺凭证时直接失败
  /// 而不是挂住等待输入。手动工具栏按钮仍走 [fetchAll]。
  Future<void> fetchAllQuiet(String dir) => _run(
    dir,
    ['fetch', '--all', '--prune'],
    environment: const {'GIT_TERMINAL_PROMPT': '0'},
  );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_history_actions_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/git/git_history_actions.dart client/test/services/git/git_history_actions_test.dart
git commit -m "feat(git): fetchAllQuiet disables terminal prompting

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: `GitAutoFetchScheduler`

**Files:**
- Create: `client/lib/services/git/git_auto_fetch_scheduler.dart`
- Test: `client/test/services/git/git_auto_fetch_scheduler_test.dart`

**Interfaces:**
- Consumes: `Future<void> Function(String dir)` fetch thunk (wired to `fetchAllQuiet` in Task 6).
- Produces: `GitAutoFetchScheduler({required Future<void> Function(String dir) fetch, required void Function() onFetched, required Duration interval, Duration timeout})` with `start(String root)`, `stop()`, `tick()` (`@visibleForTesting`), `dispose()`, getters `isRunning` / `targetRoot`. Used by Task 6.

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/git/git_auto_fetch_scheduler_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_auto_fetch_scheduler.dart';

void main() {
  List<String> fetchedRoots = [];
  int fetchedCalls = 0;
  Completer<void>? gate;

  GitAutoFetchScheduler build({Duration interval = const Duration(minutes: 5)}) {
    fetchedRoots = [];
    fetchedCalls = 0;
    return GitAutoFetchScheduler(
      fetch: (dir) async {
        fetchedCalls++;
        fetchedRoots.add(dir);
        if (gate != null) await gate!.future;
      },
      onFetched: () {},
      interval: interval,
    );
  }

  test('start fetches immediately, then every interval', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      expect(fetchedRoots, ['/repo']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/repo', '/repo']);
      async.elapse(const Duration(minutes: 10));
      expect(fetchedRoots, ['/repo', '/repo', '/repo']);
      scheduler.dispose();
    });
  });

  test('start with same running root is a no-op', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      async.flushMicrotasks();
      scheduler.start('/repo'); // must not fetch again nor reset the timer
      expect(fetchedRoots, ['/repo']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/repo', '/repo']);
      scheduler.dispose();
    });
  });

  test('start with a new root restarts and fetches immediately', () {
    fakeAsync((async) {
      final scheduler = build()..start('/a');
      async.flushMicrotasks();
      scheduler.start('/b');
      expect(fetchedRoots, ['/a', '/b']);
      async.elapse(const Duration(minutes: 5));
      expect(fetchedRoots, ['/a', '/b', '/b']);
      scheduler.dispose();
    });
  });

  test('tick while a fetch is in flight is skipped', () {
    fakeAsync((async) {
      gate = Completer<void>();
      final scheduler = build()..start('/repo');
      expect(fetchedCalls, 1);
      scheduler.tick();
      scheduler.tick();
      expect(fetchedCalls, 1, reason: 'in-flight fetch must not pile up');
      gate!.complete();
      async.flushMicrotasks();
      gate = null;
      scheduler.dispose();
    });
  });

  test('failures are swallowed and do not stop the schedule', () {
    fakeAsync((async) {
      var calls = 0;
      final scheduler = GitAutoFetchScheduler(
        fetch: (dir) async {
          calls++;
          if (calls == 1) throw StateError('fetch failed');
        },
        onFetched: () {},
        interval: const Duration(minutes: 1),
      )..start('/repo');
      async.elapse(const Duration(minutes: 1));
      expect(calls, 2, reason: 'second tick must still run after a failure');
      scheduler.dispose();
    });
  });

  test('fetch times out after the configured timeout', () {
    fakeAsync((async) {
      gate = Completer<void>();
      var fetched = 0;
      final scheduler = GitAutoFetchScheduler(
        fetch: (dir) async {
          fetched++;
          await gate!.future;
        },
        onFetched: () => fail('onFetched must not fire on timeout'),
        interval: const Duration(minutes: 5),
        timeout: const Duration(seconds: 60),
      )..start('/repo');
      async.elapse(const Duration(seconds: 61));
      expect(fetched, 1);
      gate!.complete();
      gate = null;
      scheduler.dispose();
    });
  });

  test('stop halts fetching; start resumes with an immediate fetch', () {
    fakeAsync((async) {
      final scheduler = build()..start('/repo');
      async.flushMicrotasks();
      scheduler.stop();
      async.elapse(const Duration(minutes: 30));
      expect(fetchedRoots, ['/repo']);
      scheduler.start('/repo');
      expect(fetchedRoots, ['/repo', '/repo']);
      scheduler.dispose();
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_auto_fetch_scheduler_test.dart`
Expected: FAIL — `git_auto_fetch_scheduler.dart` does not exist.

- [ ] **Step 3: Implement**

Create `client/lib/services/git/git_auto_fetch_scheduler.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';

/// 定时自动 fetch 的调度器：只负责计时与并发合并，fetch 本体由构造注入
/// （生产环境接 `GitHistoryActions.fetchAllQuiet`）。失败静默记日志——
/// 后台刷新不是用户操作，不打扰 UI；挂死的 fetch 由 [timeout] 兜底放弃。
class GitAutoFetchScheduler {
  GitAutoFetchScheduler({
    required Future<void> Function(String dir) fetch,
    required void Function() onFetched,
    required Duration interval,
    this.timeout = const Duration(seconds: 60),
  }) : _fetch = fetch,
       _onFetched = onFetched,
       _interval = interval;

  final Future<void> Function(String dir) _fetch;
  final void Function() _onFetched;
  final Duration _interval;
  final Duration timeout;

  Timer? _timer;
  String? _targetRoot;
  bool _fetchInFlight = false;

  bool get isRunning => _timer != null;
  String? get targetRoot => _targetRoot;

  /// 启动或重定向目标。已在该 root 上运行时是 no-op（不重置计时）；
  /// 否则重置计时并立即 fetch 一次——面板恢复可见/切换仓库时即刻同步。
  void start(String root) {
    if (isRunning && _targetRoot == root) return;
    _timer?.cancel();
    _targetRoot = root;
    _timer = Timer.periodic(_interval, (_) => tick());
    _fetchNow();
  }

  /// 暂停：取消计时但保留目标 root（恢复 = 对同一 root 再 [start]）。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _targetRoot = null;
  }

  @visibleForTesting
  void tick() => _fetchNow();

  Future<void> _fetchNow() async {
    final root = _targetRoot;
    if (root == null || _fetchInFlight) return;
    _fetchInFlight = true;
    try {
      await _fetch(root).timeout(timeout);
      _onFetched();
    } on Exception catch (e) {
      appLogger.w('[GitAutoFetch] fetch failed for $root: $e');
    } finally {
      _fetchInFlight = false;
    }
  }
}
```

Note: `on Exception` deliberately does not catch `Error` — programming bugs must crash tests. `TimeoutException` and `GitException` are both `Exception`s.

Check `appLogger` import path: `git_history_actions.dart` uses `import '../../utils/logging/logger.dart';` — same depth (`services/git/`), so identical import.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/git/git_auto_fetch_scheduler_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/git/git_auto_fetch_scheduler.dart client/test/services/git/git_auto_fetch_scheduler_test.dart
git commit -m "feat(git): GitAutoFetchScheduler with coalescing and timeout

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: `SessionPreferences` fields + cubit setters

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Test: `client/test/models/session_preferences_test.dart`

**Interfaces:**
- Produces: `SessionPreferences.gitAutoFetchEnabled` (`bool`, default `true`), `SessionPreferences.gitAutoFetchIntervalMinutes` (`int`, default `5`), cubit methods `Future<void> setGitAutoFetchEnabled(bool value)` and `Future<void> setGitAutoFetchIntervalMinutes(int minutes)` (clamps to 1..60). Used by Tasks 5 and 6.

- [ ] **Step 1: Write the failing tests**

In `client/test/models/session_preferences_test.dart`, add to the `SessionPreferences` group:

```dart
    test('git auto-fetch defaults on with 5 minute interval', () {
      final prefs = SessionPreferences();
      expect(prefs.gitAutoFetchEnabled, isTrue);
      expect(prefs.gitAutoFetchIntervalMinutes, 5);
    });

    test('git auto-fetch fields round-trip and fall back to defaults', () {
      final prefs = SessionPreferences(
        gitAutoFetchEnabled: false,
        gitAutoFetchIntervalMinutes: 15,
      );
      final restored = SessionPreferences.fromJson(prefs.toJson());
      expect(restored.gitAutoFetchEnabled, isFalse);
      expect(restored.gitAutoFetchIntervalMinutes, 15);

      final legacy = SessionPreferences.fromJson({
        'gitAutoFetchEnabled': null,
      });
      expect(legacy.gitAutoFetchEnabled, isTrue);
      expect(legacy.gitAutoFetchIntervalMinutes, 5);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart`
Expected: FAIL — no named parameter `gitAutoFetchEnabled`.

- [ ] **Step 3: Implement**

In `client/lib/models/session_preferences.dart`, mirror the `reclaimIdleTerminals` pattern in all four places:

1. Constructor: add `this.gitAutoFetchEnabled = true,` and `this.gitAutoFetchIntervalMinutes = 5,` (after `reclaimIdleTerminalAfterSeconds`).
2. Field declarations (after `reclaimIdleTerminalAfterSeconds`):

```dart
  /// When true (default), the source-control panel periodically runs a
  /// non-interactive `git fetch --all --prune` for the repository it shows.
  final bool gitAutoFetchEnabled;

  /// Minutes between auto-fetch ticks. UI offers 1 / 5 / 15.
  final int gitAutoFetchIntervalMinutes;
```

3. `fromJson`:

```dart
      gitAutoFetchEnabled: json['gitAutoFetchEnabled'] as bool? ?? true,
      gitAutoFetchIntervalMinutes:
          (json['gitAutoFetchIntervalMinutes'] as num?)?.toInt() ?? 5,
```

4. `copyWith`: add `bool? gitAutoFetchEnabled,` / `int? gitAutoFetchIntervalMinutes,` parameters and `gitAutoFetchEnabled: gitAutoFetchEnabled ?? this.gitAutoFetchEnabled,` / `gitAutoFetchIntervalMinutes: gitAutoFetchIntervalMinutes ?? this.gitAutoFetchIntervalMinutes,` in the body.
5. `toJson`: add `'gitAutoFetchEnabled': gitAutoFetchEnabled,` and `'gitAutoFetchIntervalMinutes': gitAutoFetchIntervalMinutes,`.

In `client/lib/cubits/session_preferences_cubit.dart`, next to `setReclaimIdleTerminals` (line ~208):

```dart
  Future<void> setGitAutoFetchEnabled(bool value) {
    return _save(
      state.preferences.copyWith(gitAutoFetchEnabled: value),
    );
  }

  Future<void> setGitAutoFetchIntervalMinutes(int minutes) {
    final clamped = minutes.clamp(1, 60);
    return _save(
      state.preferences.copyWith(gitAutoFetchIntervalMinutes: clamped),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/session_preferences.dart client/lib/cubits/session_preferences_cubit.dart client/test/models/session_preferences_test.dart
git commit -m "feat(prefs): git auto-fetch toggle and interval settings

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Settings UI + l10n

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/config/session_config_section.dart`
- Test: `client/test/pages/config/session_git_auto_fetch_settings_test.dart` (create)

**Interfaces:**
- Consumes: `gitAutoFetchEnabled` / `gitAutoFetchIntervalMinutes` + cubit setters from Task 4.
- Produces: two `TpPreferenceRow`s at the end of the session config card (switch + interval dropdown).

- [ ] **Step 1: Add l10n strings**

In `client/lib/l10n/app_en.arb` (anywhere among the flat keys; keep near other session settings):

```json
  "gitAutoFetchTitle": "Auto-fetch remote updates",
  "gitAutoFetchDescription": "Periodically run a non-interactive git fetch --all --prune for the repository shown in the source-control panel, keeping ahead/behind counts fresh.",
  "gitAutoFetchIntervalTitle": "Auto-fetch interval (minutes)",
  "gitAutoFetchIntervalDescription": "How often the selected repository is fetched while the panel is open.",
  "gitAutoFetchIntervalMinutesOption": "Every {minutes} min",
  "@gitAutoFetchIntervalMinutesOption": {
    "placeholders": {
      "minutes": {
        "type": "int"
      }
    }
  },
```

In `client/lib/l10n/app_zh.arb`, the same keys:

```json
  "gitAutoFetchTitle": "自动拉取远程更新",
  "gitAutoFetchDescription": "定时对源代码管理面板当前显示的仓库执行非交互的 git fetch --all --prune，保持提交/拉取计数最新。",
  "gitAutoFetchIntervalTitle": "自动拉取间隔（分钟）",
  "gitAutoFetchIntervalDescription": "面板打开时对选中仓库执行 fetch 的频率。",
  "gitAutoFetchIntervalMinutesOption": "每 {minutes} 分钟",
  "@gitAutoFetchIntervalMinutesOption": {
    "placeholders": {
      "minutes": {
        "type": "int"
      }
    }
  },
```

Then regenerate: `cd client && flutter gen-l10n`.

- [ ] **Step 2: Write the failing test**

Create `client/test/pages/config/session_git_auto_fetch_settings_test.dart` (mount pattern copied from `layout_region_visibility_section_test.dart`; the section reads `ConnectionModeService` — provide a default one as `session_config_section.dart` does via the app provider, or check how `ai_features_config_section_test.dart` mounts `_SessionControls` and copy that harness exactly):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/session_config_section.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('auto-fetch switch toggles and interval dropdown persists',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlocProvider<SessionPreferencesCubit>.value(
              value: cubit,
              child: const SessionConfigWorkspace(showHeading: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.preferences.gitAutoFetchEnabled, isTrue);

    final fetchSwitch = find.byType(Switch).at(
      find
          .byType(Switch)
          .evaluate()
          .indexWhere(
            (w) =>
                (w.widget as Switch).onChanged != null &&
                find
                    .descendant(
                      of: find.byWidget(w.widget),
                      matching: find.text('Auto-fetch remote updates'),
                    )
                    .evaluate()
                    .isNotEmpty,
          ),
    );
    // Fallback: locate by row title text and walk up to the Switch.
    final row = find.ancestor(
      of: find.text('Auto-fetch remote updates'),
      matching: find.byType(Switch),
    );
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(cubit.state.preferences.gitAutoFetchEnabled, isFalse);

    await tester.tap(find.text('Every 5 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 15 min').last);
    await tester.pumpAndSettle();
    expect(cubit.state.preferences.gitAutoFetchIntervalMinutes, 15);
  });
}
```

Note: the switch-locating snippet above is deliberately redundant — if `_SessionControls` mounts other switches the row-title `find.ancestor` form is the reliable one; keep whichever works and delete the other. If `SessionConfigWorkspace` needs additional scoped providers beyond `SessionPreferencesCubit` (check `ai_features_config_section_test.dart` for the exact `wrap` harness used by this section and copy it verbatim), add them.

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/session_git_auto_fetch_settings_test.dart`
Expected: FAIL — no 'Auto-fetch remote updates' text (rows not added yet).

- [ ] **Step 4: Implement the rows**

In `client/lib/pages/config/session_config_section.dart`:

1. `_SessionControlsSnapshot`: add `required this.gitAutoFetchEnabled,` / `required this.gitAutoFetchIntervalMinutes,` to the constructor, `final bool gitAutoFetchEnabled;` / `final int gitAutoFetchIntervalMinutes;` fields, wire them in `from()` (`gitAutoFetchEnabled: preferences.gitAutoFetchEnabled,` …), and include both in `==` and `hashCode` (add to the `Object.hash(...)` argument list).
2. In `_SessionControlsState.build`, after the `notifyOnSessionIdle` row (the last one), append:

```dart
                TpPreferenceRow(
                  title: l10n.gitAutoFetchTitle,
                  subtitle: l10n.gitAutoFetchDescription,
                  trailing: Switch(
                    value: snapshot.gitAutoFetchEnabled,
                    onChanged: (value) =>
                        cubit.setGitAutoFetchEnabled(value),
                  ),
                  showDividerBelow: true,
                ),
                TpPreferenceRow(
                  title: l10n.gitAutoFetchIntervalTitle,
                  subtitle: l10n.gitAutoFetchIntervalDescription,
                  trailing: DropdownButton<int>(
                    value: snapshot.gitAutoFetchIntervalMinutes,
                    items: [
                      for (final minutes in {
                        1,
                        5,
                        15,
                        snapshot.gitAutoFetchIntervalMinutes,
                      })
                        DropdownMenuItem(
                          value: minutes,
                          child: Text(
                            l10n.gitAutoFetchIntervalMinutesOption(minutes),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(cubit.setGitAutoFetchIntervalMinutes(value));
                      }
                    },
                  ),
                ),
```

The set-literal `{1, 5, 15, snapshot.gitAutoFetchIntervalMinutes}` keeps the dropdown valid for any stored value (e.g. legacy clamped values outside the offered three). `notifyOnSessionIdle`'s row currently has `showDividerBelow: false` — change it to `true` so the new rows get separators.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/session_git_auto_fetch_settings_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze + zh font check**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues. (New zh strings use no custom fonts; `sync_bundled_google_fonts.dart` is not needed unless the zh diff touches font families.)

- [ ] **Step 7: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/pages/config/session_config_section.dart client/test/pages/config/session_git_auto_fetch_settings_test.dart
git commit -m "feat(settings): auto-fetch toggle and interval in session config

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: `RightToolsLifecycleHost` wiring

**Files:**
- Modify: `client/lib/widgets/right_tools/right_tools_lifecycle.dart`
- Test: `client/test/widgets/right_tools/right_tools_auto_fetch_test.dart` (create)

**Interfaces:**
- Consumes: `GitAutoFetchScheduler` (Task 3), `fetchAllQuiet` via `GitHistoryActions.debugOverrideFactory` / `GitHistoryActions.forContext` (Task 2), `SessionPreferences.gitAutoFetchEnabled` / `gitAutoFetchIntervalMinutes` (Task 4), existing `_scope` / `_selectedGitRoot` / `_warmGit`.
- Produces: behavior — auto-fetch active iff `preferences.gitVisible && _lifecycleActive && gitAutoFetchEnabled`, target = selected root (fallback first root), immediate fetch on activation/selection change, `_warmGit()` after each successful fetch.

- [ ] **Step 1: Write the failing test**

Create `client/test/widgets/right_tools/right_tools_auto_fetch_test.dart`. Mount harness mirrors `test/widgets/git/git_source_control_panel_selection_test.dart` (storage helpers, `testRuntimeContext`, `_EmptyGitStub` via `GitService.debugOverrideFactory`); the host is mounted directly with a `WorkspaceToolsScope` ancestor:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/git/git_history_actions.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/right_tools/right_tools_lifecycle.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';

import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

class _EmptyGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async =>
      const GitRepoStatus(isRepository: false, hasCommits: false);
}

class _RecordingActions extends GitHistoryActions {
  _RecordingActions(this.fetchedRoots);

  final List<String> fetchedRoots;

  @override
  Future<void> fetchAllQuiet(String dir) async => fetchedRoots.add(dir);
}

void main() {
  late GitRepoStore store;
  late SessionPreferencesCubit prefsCubit;
  late List<String> fetchedRoots;
  late ValueNotifier<String?> selectedRoot;

  setUp(() async {
    setUpTestAppStorage();
    GitService.debugOverrideFactory = _EmptyGitStub.new;
    GitService.debugResetExecutableCache();
    store = GitRepoStore();
    fetchedRoots = [];
    GitHistoryActions.debugOverrideFactory =
        () => _RecordingActions(fetchedRoots);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    prefsCubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    await prefsCubit.load();
    selectedRoot = ValueNotifier<String?>(null);
  });

  tearDown(() async {
    GitService.debugOverrideFactory = null;
    GitService.debugResetExecutableCache();
    GitHistoryActions.debugOverrideFactory = null;
    await prefsCubit.close();
    store.dispose();
    tearDownTestAppStorage();
    selectedRoot.dispose();
  });

  Future<void> pumpHost(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: WorkspaceToolsContext(
              targetId: 'test',
              context: testRuntimeContext('/home'),
            ),
            roots: const ['/home/repoA', '/home/repoB'],
            resolving: false,
          ),
          child: BlocProvider<SessionPreferencesCubit>.value(
            value: prefsCubit,
            child: RepositoryProvider<GitRepoStore>.value(
              value: store,
              child: RightToolsLifecycleHost(
                cwd: '/home/repoA',
                additionalPaths: const ['/home/repoB'],
                workspaceId: 'ws-test',
                preferences: const RightToolsToolPreferences(
                  fileTreeVisible: false,
                  gitVisible: true,
                  searchVisible: false,
                  membersVisible: false,
                  boardVisible: false,
                ),
                child: Builder(
                  builder: (context) {
                    selectedRoot =
                        RightToolsLifecycle.of(context).selectedGitRoot;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('fetches first root on activation, follows selection, '
      'stops when disabled', (tester) async {
    await pumpHost(tester);
    // Foreground activation + scope sync + staggered disk refresh need a few
    // frames; Timer.periodic does not schedule frames so settle terminates.
    await tester.pumpAndSettle();

    expect(fetchedRoots, ['/home/repoA'],
        reason: 'immediate fetch of first root once the panel warms up');

    selectedRoot.value = '/home/repoB';
    await tester.pump();
    expect(fetchedRoots.last, '/home/repoB',
        reason: 'selection change retargets with an immediate fetch');

    await prefsCubit.setGitAutoFetchEnabled(false);
    await tester.pump();
    final countAfterDisable = fetchedRoots.length;

    selectedRoot.value = '/home/repoA';
    await tester.pumpAndSettle();
    expect(fetchedRoots.length, countAfterDisable,
        reason: 'no fetch while the setting is off');
  });

  testWidgets('no fetch when git tool is hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: WorkspaceToolsContext(
              targetId: 'test',
              context: testRuntimeContext('/home'),
            ),
            roots: const ['/home/repoA'],
            resolving: false,
          ),
          child: BlocProvider<SessionPreferencesCubit>.value(
            value: prefsCubit,
            child: RepositoryProvider<GitRepoStore>.value(
              value: store,
              child: RightToolsLifecycleHost(
                cwd: '/home/repoA',
                additionalPaths: const [],
                workspaceId: 'ws-test',
                preferences: const RightToolsToolPreferences(
                  fileTreeVisible: true,
                  gitVisible: false,
                  searchVisible: false,
                  membersVisible: false,
                  boardVisible: false,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetchedRoots, isEmpty);
  });
}
```

Note: if `_RecordingActions`'s default `GitHistoryActions()` constructor causes issues (it constructs a `LocalGitCommandRunner`, which is inert until used), it is safe — nothing calls the real runner because `fetchAllQuiet` is overridden.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/widgets/right_tools/right_tools_auto_fetch_test.dart`
Expected: FAIL — `fetchedRoots` is empty (no wiring exists yet).

- [ ] **Step 3: Implement the wiring**

In `client/lib/widgets/right_tools/right_tools_lifecycle.dart`:

1. Imports (top of file, with the existing ones):

```dart
import 'package:provider/provider.dart' show ProviderNotFoundException;

import '../../cubits/session_preferences_cubit.dart';
import '../../models/session_preferences.dart';
import '../../services/git/git_auto_fetch_scheduler.dart';
import '../../services/git/git_history_actions.dart';
```

(`context.read` itself comes from `flutter_bloc`, already imported.)

2. State fields (next to `_diskPollTimer`):

```dart
  GitAutoFetchScheduler? _autoFetchScheduler;
  GitHistoryActions? _autoFetchActions;
  String? _autoFetchTargetId;
  Duration? _autoFetchIntervalUsed;
  StreamSubscription<SessionPreferencesState>? _sessionPrefsSub;
  bool _sessionPrefsResolved = false;
  bool _autoFetchEnabled = true;
  int _autoFetchIntervalMinutes = 5;
```

3. `initState` (create if absent — the class currently has no `initState`; add one before `didChangeDependencies`):

```dart
  @override
  void initState() {
    super.initState();
    _selectedGitRoot.addListener(_onSelectedGitRootChanged);
  }
```

4. `didChangeDependencies` — resolve the cubit once, before `_onForegroundChanged()`:

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveSessionPreferences();
    _onForegroundChanged();
  }
```

```dart
  /// Resolves the app-level session preferences once; standalone test mounts
  /// without the provider are fine (auto-fetch simply stays default-config).
  void _resolveSessionPreferences() {
    if (_sessionPrefsResolved) return;
    _sessionPrefsResolved = true;
    final SessionPreferencesCubit cubit;
    try {
      cubit = context.read<SessionPreferencesCubit>();
    } on ProviderNotFoundException {
      return;
    }
    _applySessionPreferences(cubit.state.preferences);
    _sessionPrefsSub = cubit.stream.listen(
      (state) => _applySessionPreferences(state.preferences),
    );
  }

  void _applySessionPreferences(SessionPreferences prefs) {
    final enabled = prefs.gitAutoFetchEnabled;
    final minutes = prefs.gitAutoFetchIntervalMinutes;
    if (enabled == _autoFetchEnabled && minutes == _autoFetchIntervalMinutes) {
      return;
    }
    _autoFetchEnabled = enabled;
    _autoFetchIntervalMinutes = minutes;
    if (mounted) _syncAutoFetchScheduler();
  }

  void _onSelectedGitRootChanged() {
    if (mounted) _syncAutoFetchScheduler();
  }
```

5. Sync + suspend integration. Call `_autoFetchScheduler?.stop();` inside `_suspendDiskSideEffects` (after `_diskPollTimer?.cancel();`), and call `_syncAutoFetchScheduler();` at the end of `_setupDiskRefresh` (after `_diskListenersActive = true;`) and at the end of `_resumeDiskSideEffects`. Then:

```dart
  /// Auto-fetch runs only while the git tool is enabled, the lifecycle is
  /// foreground-active (see [_setupDiskRefresh] / [_suspendDiskSideEffects]),
  /// and the user setting is on. Target root mirrors the status panel's
  /// selection (fallback: first root — same semantics as
  /// [GitRepoStore.refreshAll]).
  void _syncAutoFetchScheduler() {
    final tools = _scope?.tools;
    final roots = _scope?.roots ?? const <String>[];
    final selected = _selectedGitRoot.value;
    final target =
        selected != null && roots.contains(selected)
        ? selected
        : (roots.isNotEmpty ? roots.first : null);

    if (tools == null || target == null ||
        !_autoFetchEnabled || !widget.preferences.gitVisible) {
      _autoFetchScheduler?.stop();
      return;
    }

    var actionsChanged = _autoFetchActions == null ||
        _autoFetchTargetId != tools.targetId;
    if (actionsChanged) {
      _autoFetchActions =
          GitHistoryActions.debugOverrideFactory?.call() ??
          GitHistoryActions.forContext(tools.context);
      _autoFetchTargetId = tools.targetId;
    }

    final interval = Duration(minutes: _autoFetchIntervalMinutes);
    if (actionsChanged ||
        _autoFetchScheduler == null ||
        _autoFetchIntervalUsed != interval) {
      // Actions or interval changed: the old scheduler's fetch closure is
      // stale — replace the whole scheduler (its in-flight fetch, if any,
      // completes harmlessly).
      _autoFetchScheduler?.dispose();
      _autoFetchIntervalUsed = interval;
      final actions = _autoFetchActions!;
      _autoFetchScheduler = GitAutoFetchScheduler(
        fetch: actions.fetchAllQuiet,
        onFetched: _warmGit,
        interval: interval,
      );
    }
    _autoFetchScheduler!.start(target);
  }
```

6. `dispose()` — add before `_selectedGitRoot.dispose();`:

```dart
    _sessionPrefsSub?.cancel();
    _autoFetchScheduler?.dispose();
    _selectedGitRoot.removeListener(_onSelectedGitRootChanged);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/widgets/right_tools/right_tools_auto_fetch_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Run neighboring tests for regressions**

Run: `cd client && dart run tool/run_tests.dart test/widgets/git/ test/cubits/git_cubit_test.dart test/services/git/git_repo_store_refresh_test.dart`
Expected: PASS — the lifecycle changes must not disturb the disk-refresh machinery.

- [ ] **Step 6: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new issues.

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/right_tools/right_tools_lifecycle.dart client/test/widgets/right_tools/right_tools_auto_fetch_test.dart
git commit -m "feat(git): wire auto-fetch into right-tools lifecycle

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: clean (no new issues vs. `main`).

- [ ] **Step 2: Full test suite (background)**

Run: `cd client && dart run tool/run_tests.dart` in the background; wait for completion.
Expected: PASS. Any pre-existing failures on `main` should be compared against this run — only regressions introduced by this plan block completion.

- [ ] **Step 3: Manual smoke check (optional but recommended)**

Launch the app (`cd client && flutter run -d linux` or the project's standard run command), open a workspace with a git repo, open the source-control panel, and confirm via `git log origin/<branch>` timestamps (or a temporary `appLogger` breakpoint) that a fetch fires within a minute of the panel warming up. Toggle the setting off and confirm no further fetches.

---

## Spec deviations (documented deliberately)

- The spec's scheduler API listed `replaceTarget(root)`; the implemented API folds it into `start(root)` with "no-op if already running on the same root, else restart + immediate fetch" semantics — one method, no paused/stopped ambiguity. The spec file is updated in the same commit as the plan to match.

## Self-review notes

- Spec coverage: settings model (Task 4), settings UI + l10n (Task 5), `fetchAllQuiet` env + 60s timeout (Tasks 1-3), scheduler coalescing/silent failures (Task 3), lifecycle gating/target/refresh hookup (Task 6), tests per spec section (Tasks 1-6), all backends inherit env passthrough via `HostRunRequest.environment` (Task 1 — Local merges via `Process.run`, WSL prefixes `env K=V`, Remote embeds in the shell command).
- Type consistency: `fetchAllQuiet(String dir)` (Task 2) matches the `fetch` thunk type `Future<void> Function(String dir)` (Task 3) and `actions.fetchAllQuiet` tear-off (Task 6). `GitAutoFetchScheduler` constructor args identical in Tasks 3 and 6.
- Known risk flagged for the implementer: the Task 5 test's switch/dropdown locating logic may need adjusting to the actual harness (`ai_features_config_section_test.dart` is the reference for how this section mounts).
