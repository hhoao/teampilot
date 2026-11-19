# Install Job Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every install job a live, persisted log that can be opened from the progress dialog and from the completion notification.

**Architecture:** `InstallJobRegistry` owns a `JobLogStore` that writes one file per job under `<nativeAppDataRoot>/logs/install-jobs/`, keeps a 2000-line ring buffer, and exposes a broadcast stream. `InstallJobContext` carries a nullable `appendLog` callback so runners can forward process output without knowing about storage. CLI output reaches it through `CliInstallerService` (local streaming already exists; SSH gains a streaming runner over `SshClientFactory.startProcess`). The notification payload `install-log:<token>` opens the same `JobLogDialog`.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing `Filesystem` abstraction, `package:shared_ui` dialogs, slang l10n.

## Global Constraints

- Never run `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths>`.
- Inner loop is `cd client && flutter analyze`; run only the test directories covering the change.
- l10n: edit `client/lib/i18n/<ns>_en.i18n.json` and `_zh.i18n.json`, then `cd client && dart run slang` (never build_runner).
- Diagnostics via `AppLogger`; user-facing strings via l10n. No `print`.
- Log files live under the **native** app data root (`AppPathsBootstrapper.current.basePath` / `nativeAppDataPath`), never the remote home plane.
- Do not modify unrelated dirty files in the worktree (there are pre-existing local changes).
- Commits stage only the files named in each task.

---

### Task 1: `JobLogStore` and writer

**Files:**
- Create: `client/lib/services/install/job_log_store.dart`
- Test: `client/test/services/install/job_log_store_test.dart`

**Interfaces:**
- Consumes: `InstallJobKey` (`models/install_job/install_job_key.dart`, `String get activityId`), `Filesystem` (`services/io/filesystem.dart`: `appendString`, `writeString`, `readString`, `listDir`, `stat`, `removeRecursive`, `ensureDir`), `LocalFilesystem`.
- Produces:
  - `JobLogStore({required String appDataRoot, Filesystem? fs, DateTime Function()? now})`
  - `String tokenFor(InstallJobKey key)`
  - `JobLogWriter begin({required InstallJobKey key, required String title})`
  - `bool isLive(String token)`
  - `Stream<String> follow(String token)`
  - `Future<List<String>> read(String token)`
  - `Future<void> purge()`
  - `JobLogWriter` with `void line(String text)` and `Future<void> close()`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/install/job_log_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/services/install/job_log_store.dart';

import '../../support/in_memory_filesystem.dart';

const _key = InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: 'claude:remote',
);

void main() {
  group('JobLogStore tokens', () {
    test('sanitizes unsafe characters and stays deterministic', () {
      final store = JobLogStore(
        appDataRoot: '/tp',
        fs: InMemoryFilesystem(),
      );
      final token = store.tokenFor(_key);
      expect(token, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
      expect(store.tokenFor(_key), token);
      expect(token, contains('claude_remote'));
    });

    test('different keys get different tokens', () {
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      const other = InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'codex',
      );
      expect(store.tokenFor(_key), isNot(store.tokenFor(other)));
    });
  });

  group('JobLogStore writing', () {
    test('writes header and lines in order and closes the live stream', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 'Install Claude');
      final events = <String>[];
      final sub = store.follow(token).listen(events.add);

      writer.line('first');
      writer.line('second');
      await writer.close();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(store.isLive(token), isFalse);
      expect(events.length, 3);
      expect(events[0], startsWith('[start]'));
      expect(events[1], 'first');
      expect(events[2], 'second');

      final file = p.join('/tp', 'logs', 'install-jobs', '$token.log');
      final onDisk = utf8.decode(fs.byteFiles[file]!);
      expect(onDisk.split('\n')[1], 'first');
      expect(await store.read(token), isNotEmpty);
    });

    test('strips ANSI escapes and keeps the last carriage-return render',
        () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 't');
      writer.line('\u001b[32m50%\u001b[0m progress');
      writer.line('10%\rdone');
      await writer.close();

      final lines = await store.read(token);
      expect(lines[1], '50% progress');
      expect(lines[2], 'done');
      expect(lines.join('\n'), isNot(contains('\u001b')));
    });

    test('caps a single line at 4096 characters', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 't');
      writer.line('x' * 10000);
      await writer.close();

      final lines = await store.read(token);
      expect(lines[1].length, 4096);
    });

    test('ring buffer keeps the newest 2000 lines', () async {
      final fs = InMemoryFilesystem();
      final store = JobLogStore(appDataRoot: '/tp', fs: fs);
      final token = store.tokenFor(_key);
      final writer = store.begin(key: _key, title: 't');
      for (var i = 0; i < 2100; i++) {
        writer.line('line $i');
      }
      final replayed = <String>[];
      final sub = store.follow(token).listen(replayed.add);
      await writer.close();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // The file keeps every line; the live replay is the 2000-line ring.
      expect(replayed.length, 2000);
      expect(replayed.first, 'line 100');
      expect(replayed.last, 'line 2099');
      expect((await store.read(token)).length, 2101);
    });

    test('returns empty for an unknown token', () async {
      final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
      expect(await store.read('missing'), isEmpty);
      expect(store.isLive('missing'), isFalse);
      expect(await store.follow('missing').toList(), isEmpty);
    });
  });

  group('JobLogStore purge', () {
    late Directory root;
    late JobLogStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('job-log-test-');
      store = JobLogStore(appDataRoot: root.path);
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('removes files older than 7 days', () async {
      final dir = Directory(p.join(root.path, 'logs', 'install-jobs'))
        ..createSync(recursive: true);
      final old = File(p.join(dir.path, 'old.log'))
        ..writeAsStringSync('[start]\n')
        ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
      final fresh = File(p.join(dir.path, 'fresh.log'))
        ..writeAsStringSync('[start]\n');

      await store.purge();

      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test('keeps at most 20 newest files', () async {
      final dir = Directory(p.join(root.path, 'logs', 'install-jobs'))
        ..createSync(recursive: true);
      final files = <File>[];
      for (var i = 0; i < 25; i++) {
        final file = File(p.join(dir.path, 'job$i.log'))
          ..writeAsStringSync('[start]\n')
          ..setLastModifiedSync(DateTime.now().subtract(Duration(minutes: i)));
        files.add(file);
      }

      await store.purge();

      final remaining = dir.listSync().whereType<File>().toList();
      expect(remaining.length, 20);
      expect(File(p.join(dir.path, 'job0.log')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'job24.log')).existsSync(), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/install/job_log_store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: .../job_log_store.dart`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/install/job_log_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/install_job/install_job_key.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';

const jobLogMaxRingLines = 2000;
const jobLogMaxLineChars = 4096;
const jobLogMaxFileBytes = 5 * 1024 * 1024;
const jobLogMaxFiles = 20;
const jobLogMaxAge = Duration(days: 7);

final _ansiPattern = RegExp(
  r'\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07]*(?:\x07|\x1B\\)',
);

int _fnv1a32(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

final class JobLogWriter {
  JobLogWriter._(this._owner, this._token);

  final JobLogStore _owner;
  final String _token;

  void line(String text) => _owner._append(_token, text);

  Future<void> close() => _owner._close(_token);
}

final class JobLogStore {
  JobLogStore({
    required String appDataRoot,
    Filesystem? fs,
    DateTime Function()? now,
  }) : _fs = fs ?? LocalFilesystem(),
       _now = now ?? DateTime.now,
       _dir = p.join(appDataRoot, 'logs', 'install-jobs') {
    unawaited(purge());
  }

  final Filesystem _fs;
  final DateTime Function() _now;
  final String _dir;
  final Map<String, _LiveJobLog> _live = {};

  String tokenFor(InstallJobKey key) {
    final raw = key.activityId;
    final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final hash = _fnv1a32(raw).toRadixString(16).padLeft(8, '0');
    return '$sanitized-$hash';
  }

  JobLogWriter begin({required InstallJobKey key, required String title}) {
    final token = tokenFor(key);
    final log = _LiveJobLog(path: _pathFor(token));
    _live[token] = log;
    final stamp = _now().toIso8601String();
    final header = '[start] $stamp — $title';
    log.lines.add(header);
    log.controller.add(header);
    final chunk = '$header\n';
    log.bytes = chunk.length;
    // Truncate: a rerun of the same job starts a fresh file instead of
    // appending to the previous run. Bytes, not writeString, so the fake's
    // UTF-16 code-unit storage cannot corrupt non-ASCII output.
    log.fileChain = _fs.writeBytes(log.path, utf8.encode(chunk)).catchError((
      Object _,
    ) {
      log.dropped = true;
    });
    return JobLogWriter._(this, token);
  }

  bool isLive(String token) => _live.containsKey(token);

  Stream<String> follow(String token) {
    final log = _live[token];
    if (log == null) return const Stream<String>.empty();
    return log.subscribe();
  }

  Future<List<String>> read(String token) async {
    final raw = await _fs.readString(_pathFor(token));
    if (raw == null || raw.isEmpty) return const <String>[];
    return const LineSplitter().convert(raw);
  }

  Future<void> purge() async {
    try {
      final entries = await _fs.listDir(_dir);
      final files = <(String, DateTime)>[];
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        final path = p.join(_dir, entry.name);
        final stat = await _fs.stat(path);
        if (!stat.isFile) continue;
        files.add((path, stat.mtime ?? _now()));
      }
      final cutoff = _now().subtract(jobLogMaxAge);
      for (final entry in files) {
        if (entry.$2.isBefore(cutoff)) {
          await _fs.removeRecursive(entry.$1);
        }
      }
      final alive = [
        for (final entry in files)
          if (!entry.$2.isBefore(cutoff)) entry,
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in alive.skip(jobLogMaxFiles)) {
        await _fs.removeRecursive(entry.$1);
      }
    } on Object {
      // Purge is best effort; a missing dir or locked file must not break boot.
    }
  }

  String _pathFor(String token) => p.join(_dir, '$token.log');

  void _append(String token, String text) {
    final log = _live[token];
    if (log == null) return;
    final cleaned = text
        .replaceAll(_ansiPattern, '')
        .split('\r')
        .last
        .trimRight();
    if (cleaned.isEmpty) return;
    final lineText = cleaned.length > jobLogMaxLineChars
        ? cleaned.substring(0, jobLogMaxLineChars)
        : cleaned;

    log.lines.add(lineText);
    if (log.lines.length > jobLogMaxRingLines) log.lines.removeAt(0);
    log.controller.add(lineText);

    if (log.dropped) return;
    final chunk = '$lineText\n';
    if (log.bytes + chunk.length > jobLogMaxFileBytes) {
      log.dropped = true;
      log.fileChain = log.fileChain
          .then((_) => _fs.appendBytes(log.path, utf8.encode('[truncated]\n')))
          .catchError((Object _) {});
      return;
    }
    log.bytes += chunk.length;
    log.fileChain = log.fileChain
        .then((_) => _fs.appendBytes(log.path, utf8.encode(chunk)))
        .catchError((Object _) {
          log.dropped = true;
        });
  }

  Future<void> _close(String token) async {
    final log = _live.remove(token);
    if (log == null) return;
    await log.fileChain;
    await log.controller.close();
  }
}

final class _LiveJobLog {
  _LiveJobLog({required this.path});

  final String path;
  final List<String> lines = <String>[];
  final StreamController<String> controller = StreamController<String>.broadcast();
  Future<void> fileChain = Future<void>.value();
  int bytes = 0;
  bool dropped = false;

  Stream<String> subscribe() async* {
    yield* Stream<String>.fromIterable(List<String>.of(lines));
    yield* controller.stream;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/install/job_log_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/install/job_log_store.dart client/test/services/install/job_log_store_test.dart
git commit -m "feat(install): add per-job install log store"
```

---

### Task 2: SSH streaming command runner

**Files:**
- Create: `client/lib/services/cli/ssh_streaming_command_runner.dart`
- Test: `client/test/services/cli/ssh_streaming_command_runner_test.dart`

**Interfaces:**
- Consumes: `ProcessRunHandle` (`services/host/process_run_handle.dart`: `Future<int> exitCode`, `Stream<List<int>> stdout/stderr`, `void kill()`), `CliInstallerCommandResult`/`CliInstallerCommand` (`services/cli/installer_types.dart`), `SshStorageIo.provisionPhaseTimeout` (`services/ssh/ssh_storage_io.dart`), `SshProfile`.
- Produces:
  - `typedef SshProcessStarter = Future<ProcessRunHandle> Function(SshProfile profile, String command);`
  - `SshStreamingCommandRunner({required SshProcessStarter startProcess, Duration timeout, int maxCapturedChars})`
  - `Future<CliInstallerCommandResult> run(SshProfile profile, CliInstallerCommand command, {void Function(String line)? onOutput})`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/ssh_streaming_command_runner_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/ssh_streaming_command_runner.dart';
import 'package:teampilot/services/host/process_run_handle.dart';

final class _FakeHandle implements ProcessRunHandle {
  _FakeHandle({this.exit = 0, this.hang = false});

  final int exit;
  final bool hang;
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  var killed = false;

  @override
  Future<int> get exitCode => hang
      ? Completer<int>().future
      : Future<int>.value(exit);

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  void kill() => killed = true;

  Future<void> close() async {
    await stdoutController.close();
    await stderrController.close();
  }
}

SshProfile _profile() => const SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.com',
  port: 22,
  username: 'u',
);

void main() {
  test('forwards stdout and stderr lines and returns the exit code', () async {
    final handle = _FakeHandle(exit: 0);
    final lines = <String>[];
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('npm i -g x'),
      onOutput: lines.add,
    );
    handle.stdoutController.add(utf8.encode('one\ntwo\n'));
    handle.stderrController.add(utf8.encode('warn\n'));
    await handle.close();
    final result = await future;

    expect(lines, ['one', 'two', 'warn']);
    expect(result.exitCode, 0);
    expect(result.stdout, contains('two'));
    expect(result.stderr, contains('warn'));
  });

  test('kills the process and reports 124 on timeout', () async {
    final handle = _FakeHandle(hang: true);
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
      timeout: const Duration(milliseconds: 20),
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('sleep 100'),
    );
    await handle.close();
    final result = await future;

    expect(handle.killed, isTrue);
    expect(result.exitCode, 124);
    expect(result.stderr, contains('timed out'));
  });

  test('captures only the tail of very large output', () async {
    final handle = _FakeHandle(exit: 0);
    final runner = SshStreamingCommandRunner(
      startProcess: (profile, command) async => handle,
      maxCapturedChars: 50,
    );

    final future = runner.run(
      _profile(),
      CliInstallerCommand.unixShellScript('yes x'),
    );
    handle.stdoutController.add(utf8.encode('${'a' * 40}\n${'b' * 40}\n'));
    await handle.close();
    final result = await future;

    expect(result.stdout.length, lessThanOrEqualTo(50));
    expect(result.stdout, contains('bbb'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/ssh_streaming_command_runner_test.dart`
Expected: FAIL — missing import/class.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/cli/ssh_streaming_command_runner.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../host/process_run_handle.dart';
import '../ssh/ssh_storage_io.dart';
import 'installer_types.dart';

typedef SshProcessStarter =
    Future<ProcessRunHandle> Function(SshProfile profile, String command);

final class SshStreamingCommandRunner {
  SshStreamingCommandRunner({
    required SshProcessStarter startProcess,
    this.timeout = SshStorageIo.provisionPhaseTimeout,
    this.maxCapturedChars = 1 << 20,
  }) : _startProcess = startProcess;

  final SshProcessStarter _startProcess;
  final Duration timeout;
  final int maxCapturedChars;

  Future<CliInstallerCommandResult> run(
    SshProfile profile,
    CliInstallerCommand command, {
    void Function(String line)? onOutput,
  }) async {
    ProcessRunHandle handle;
    try {
      handle = await _startProcess(profile, command.commandLine);
    } on Object catch (error) {
      return CliInstallerCommandResult(exitCode: 1, stderr: error.toString());
    }

    final stdoutTail = _TailBuffer(maxCapturedChars);
    final stderrTail = _TailBuffer(maxCapturedChars);

    Future<void> drain(Stream<List<int>> stream, _TailBuffer tail) async {
      await stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            tail.add(line);
            onOutput?.call(line);
          });
    }

    try {
      final exitCode = await () async {
        await Future.wait([
          drain(handle.stdout, stdoutTail),
          drain(handle.stderr, stderrTail),
        ]);
        return handle.exitCode;
      }().timeout(timeout);

      return CliInstallerCommandResult(
        exitCode: exitCode,
        stdout: stdoutTail.text,
        stderr: stderrTail.text,
      );
    } on TimeoutException {
      handle.kill();
      return CliInstallerCommandResult(
        exitCode: 124,
        stdout: stdoutTail.text,
        stderr: 'timed out',
      );
    } on Object catch (error) {
      handle.kill();
      return CliInstallerCommandResult(exitCode: 1, stderr: error.toString());
    }
  }
}

final class _TailBuffer {
  _TailBuffer(this.maxChars);

  final int maxChars;
  final List<String> _lines = <String>[];
  int _chars = 0;

  void add(String line) {
    _lines.add(line);
    _chars += line.length + 1;
    while (_chars > maxChars && _lines.length > 1) {
      _chars -= _lines.removeAt(0).length + 1;
    }
  }

  String get text => _lines.join('\n');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/ssh_streaming_command_runner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/ssh_streaming_command_runner.dart client/test/services/cli/ssh_streaming_command_runner_test.dart
git commit -m "feat(cli): add streaming SSH command runner for installs"
```

---

### Task 3: `ProgressActivity.logToken` and cubit payload

**Files:**
- Modify: `client/lib/models/progress_activity.dart`
- Modify: `client/lib/cubits/progress_activity_cubit.dart`
- Test: `client/test/cubits/progress_activity_cubit_test.dart` (extend)

**Interfaces:**
- Produces:
  - `ProgressActivity.logToken` (`String?`)
  - `ProgressActivityCubit.startForInstallJob({..., String? logToken})`
  - `ProgressActivityCubit.complete({..., String? historyPayload})`

- [ ] **Step 1: Write the failing test**

Open `client/test/cubits/progress_activity_cubit_test.dart`. It already defines
`_FakeNotificationRecorder`. Change its record tuple and implementation to carry
`payload`:

```dart
class _FakeNotificationRecorder implements NotificationRecorder {
  final records =
      <({String message, TpToastVariant variant, String title, String payload})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((
      message: message,
      variant: variant,
      title: title,
      payload: payload,
    ));
  }
}
```

Add these imports at the top:

```dart
import 'package:teampilot/models/install_job/install_job_key.dart';
```

Append a new group at the end of `void main()`:

```dart
  group('install log token', () {
    test('install activity carries logToken and completes with payload', () {
      final recorder = _FakeNotificationRecorder();
      final cubit = ProgressActivityCubit(historyRecorder: recorder);
      addTearDown(cubit.close);
      const key = InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'claude',
      );

      cubit.startForInstallJob(
        jobKey: key,
        title: 'Install Claude',
        kind: ProgressActivityKind.cliProvision,
        logToken: 'tok-1',
      );

      expect(cubit.state.activities.single.logToken, 'tok-1');

      cubit.complete(
        key.activityId,
        outcome: ProgressActivityPhase.succeeded,
        historyTitle: 'Install Claude',
        historyPayload: 'install-log:tok-1',
      );

      expect(cubit.state.activities, isEmpty);
      expect(recorder.records.single.payload, 'install-log:tok-1');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/progress_activity_cubit_test.dart`
Expected: FAIL — `logToken`/`historyPayload` not defined.

- [ ] **Step 3: Implement**

In `client/lib/models/progress_activity.dart`:

1. Add field `final String? logToken;` after `jobKey`.
2. Add `this.logToken,` to the constructor.
3. Add `String? logToken,` to `copyWith` and `logToken: logToken ?? this.logToken,` in the body.
4. Add `logToken,` to `props`.

In `client/lib/cubits/progress_activity_cubit.dart`:

1. `startForInstallJob` gains `String? logToken` and passes `logToken: logToken` into `ProgressActivity(...)`.
2. `update()` constructs a new `ProgressActivity`; add `logToken: current.logToken,`.
3. `complete()` gains `String? historyPayload`; pass it at the recorder call:

```dart
    _historyRecorder.record(
      message: message,
      variant: variant,
      title: title,
      payload: historyPayload ?? '',
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/progress_activity_cubit_test.dart test/widgets/progress_activity`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/progress_activity.dart client/lib/cubits/progress_activity_cubit.dart client/test/cubits/progress_activity_cubit_test.dart
git commit -m "feat(progress): carry install log token through progress activities"
```

---

### Task 4: Registry integration and wiring

**Files:**
- Modify: `client/lib/models/install_job/install_job_context.dart`
- Modify: `client/lib/services/install/install_job_registry.dart`
- Modify: `client/lib/app/bootstrap/install_wiring.dart`
- Modify: `client/lib/app/app_shell.dart` (pass `nativeAppDataPath`)
- Test: `client/test/services/install/install_job_registry_test.dart`

**Interfaces:**
- Consumes: Task 1 `JobLogStore`/`JobLogWriter`, Task 3 `startForInstallJob(logToken:)` and `complete(historyPayload:)`.
- Produces: `InstallJobContext.appendLog` (`void Function(String line)?`), `InstallJobRegistry({..., JobLogStore? logs})`, `JobLogStore? get logs`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/install/install_job_registry_test.dart` inside `void main()` (after the existing group), and update the file imports to add:

```dart
import 'package:teampilot/services/install/job_log_store.dart';

import '../../support/in_memory_filesystem.dart';
```

Also extend the file's existing `_FakeNotificationRecorder` tuple to include
`payload` so the assertions below compile:

```dart
class _FakeNotificationRecorder implements NotificationRecorder {
  final records =
      <({String message, TpToastVariant variant, String title, String payload})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {
    records.add((
      message: message,
      variant: variant,
      title: title,
      payload: payload,
    ));
  }
}
```

New group:

```dart
  group('InstallJobRegistry logs', () {
    late _FakeNotificationRecorder recorder;
    late ProgressActivityCubit progressCubit;
    late InMemoryFilesystem fs;
    late JobLogStore logs;
    late InstallJobRegistry registry;

    setUp(() {
      recorder = _FakeNotificationRecorder();
      progressCubit = ProgressActivityCubit(historyRecorder: recorder);
      fs = InMemoryFilesystem();
      logs = JobLogStore(appDataRoot: '/tp', fs: fs);
      registry = InstallJobRegistry(progressCubit: progressCubit, logs: logs);
    });

    tearDown(() {
      registry.dispose();
      progressCubit.close();
    });

    const key = InstallJobKey(
      kind: InstallJobKind.cliExecutable,
      target: 'claude',
    );

    test('writes start, phase, output and ok lines, then closes', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<String>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          ctx.reportPhase('Installing CLI', detail: 'npm install');
          ctx.appendLog?.call('added 1 package');
          return 'done';
        },
      );

      await registry.enqueue(spec);

      expect(logs.isLive(token), isFalse);
      final lines = await logs.read(token);
      expect(lines.first, startsWith('[start]'));
      expect(lines, contains('[phase] Installing CLI — npm install'));
      expect(lines, contains('added 1 package'));
      expect(lines.last, startsWith('[ok]'));
      expect(recorder.records.single.payload, 'install-log:$token');
    });

    test('writes fail line with the error message', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async => throw StateError('boom'),
      );

      await expectLater(registry.enqueue(spec), throwsStateError);

      final lines = await logs.read(token);
      expect(lines.last, '[fail] Bad state: boom');
      expect(recorder.records.single.payload, 'install-log:$token');
    });

    test('writes cancel line on cooperative cancel', () async {
      final token = logs.tokenFor(key);
      final spec = InstallJobSpec<void>(
        key: key,
        title: 'Install Claude',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async {
          while (!ctx.isCancelled) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        },
      );

      final future = registry.enqueue(spec);
      final expectation = expectLater(future, throwsA(isA<Exception>()));
      registry.requestCancel(key);
      await expectation;

      final lines = await logs.read(token);
      expect(lines.last, '[cancel]');
    });
  });
```

Note: the cancel test asserts `throwsA(isA<Exception>())` because `InstallJobCancelledException` implements `Exception`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/install/install_job_registry_test.dart`
Expected: FAIL — `logs` named argument not defined; `appendLog` missing.

- [ ] **Step 3: Implement**

`client/lib/models/install_job/install_job_context.dart`:

```dart
final class InstallJobContext {
  InstallJobContext({
    void Function(String label, {String? detail, double? fraction})?
    reportPhase,
    void Function({required int completed, required int total})? reportItems,
    this.appendLog,
  }) : _reportPhase = reportPhase,
       _reportItems = reportItems;

  final void Function(String line)? appendLog;
  ...
```

(Keep the existing private fields and methods unchanged.)

`client/lib/services/install/install_job_registry.dart`:

1. Import `job_log_store.dart`.
2. Constructor:

```dart
  InstallJobRegistry({
    required ProgressActivityCubit progressCubit,
    InstallJobRunnerRegistry? runnerRegistry,
    JobLogStore? logs,
  }) : _progressCubit = progressCubit,
       _runnerRegistry = runnerRegistry,
       _logs = logs;

  final JobLogStore? _logs;
  JobLogStore? get logs => _logs;
```

3. In `enqueue`, before creating `ctx`:

```dart
    final token = _logs?.tokenFor(spec.key);
    final writer = _logs?.begin(key: spec.key, title: spec.title);
    final payload = token == null ? '' : 'install-log:$token';
```

4. `reportPhase` becomes:

```dart
      reportPhase: (label, {detail, fraction}) {
        final subtitle = detail == null ? label : '$label — $detail';
        writer?.line('[phase] $subtitle');
        _progressCubit.update(
          activityId,
          subtitle: subtitle,
          fraction: fraction,
        );
        _emitSnapshot(
          spec.key,
          InstallJobPhase.running,
          subtitle: subtitle,
          fraction: fraction,
        );
      },
```

5. `reportItems` unchanged.
6. Context creation adds `appendLog: writer?.line,`.
7. `_ActiveJob` constructor gains `required this.writer, required this.payload,` and fields:

```dart
  final JobLogWriter? writer;
  final String payload;
```

8. Pass them in the `_ActiveJob(...)` literal:
```dart
      writer: writer,
      payload: payload,
```

9. `startForInstallJob(...)` gains `logToken: token,`.
10. Every `_progressCubit.complete(...)` call in `_runJob` and `_completeCancelled` gains `historyPayload: job.payload,`.
11. Terminal lines must be flushed **before** the job's future completes, so an
    immediately-opened log dialog never misses the tail. Change `_runJob` to:

```dart
  Future<void> _runJob(_ActiveJob job) async {
    final activityId = job.key.activityId;
    try {
      final result = await job.run(job.ctx);
      if (job.ctx.isCancelled) {
        await _completeCancelled(job);
        return;
      }

      await job.onSucceeded?.call(result);
      final message = job.historyMessageFor?.call(result);
      job.writer?.line(message == null ? '[ok]' : '[ok] $message');
      await job.writer?.close();
      _progressCubit.complete(
        activityId,
        outcome: ProgressActivityPhase.succeeded,
        historyTitle: job.historyTitle,
        historyMessage: message,
        historyPayload: job.payload,
      );
      _emitSnapshot(job.key, InstallJobPhase.succeeded);
      job.markTerminal();
      job.completer.complete(result);
    } on InstallJobCancelledException {
      await _completeCancelled(job);
    } catch (error, stackTrace) {
      await job.onFailed?.call(error);
      job.writer?.line('[fail] $error');
      await job.writer?.close();
      _progressCubit.complete(
        activityId,
        outcome: ProgressActivityPhase.failed,
        errorMessage: error.toString(),
        historyTitle: job.historyTitle,
        historyPayload: job.payload,
      );
      _emitSnapshot(job.key, InstallJobPhase.failed);
      job.markTerminal();
      job.completer.completeError(error, stackTrace);
    } finally {
      _active.remove(job.key);
    }
  }
```

And `_completeCancelled`:

```dart
  Future<void> _completeCancelled(_ActiveJob job) async {
    job.writer?.line('[cancel]');
    await job.writer?.close();
    _progressCubit.complete(
      job.key.activityId,
      outcome: ProgressActivityPhase.cancelled,
      historyTitle: job.historyTitle,
      historyPayload: job.payload,
    );
    _emitSnapshot(job.key, InstallJobPhase.cancelled);
    job.markTerminal();
    job.completer.completeError(InstallJobCancelledException(job.key));
  }
```

`client/lib/app/bootstrap/install_wiring.dart`:

1. Import `../services/install/job_log_store.dart`.
2. `wireInstallJobs` gains `required String appLogRoot,`.
3. Build the store and pass it:

```dart
  final jobLogs = JobLogStore(appDataRoot: appLogRoot);
  ...
  final installJobRegistry = InstallJobRegistry(
    progressCubit: progressActivity,
    runnerRegistry: installJobRunnerRegistry,
    logs: jobLogs,
  );
```

`client/lib/app/app_shell.dart`: in the `wireInstallJobs(` call at ~line 1167 add `appLogRoot: nativeAppDataPath,`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/install test/widgets/progress_activity`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze`
Expected: no new issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/install_job/install_job_context.dart \
  client/lib/services/install/install_job_registry.dart \
  client/lib/app/bootstrap/install_wiring.dart \
  client/lib/app/app_shell.dart \
  client/test/services/install/install_job_registry_test.dart
git commit -m "feat(install): record install job logs in the registry"
```

---

### Task 5: CLI installer output plumbing

**Files:**
- Modify: `client/lib/services/cli/cli_installer_service.dart`
- Modify: `client/lib/services/install/runners/cli_install_job_runner.dart`
- Modify: `client/test/services/install/runners/cli_install_job_runner_test.dart`
- Modify: `client/test/pages/config/cli_config_section_test.dart`

**Interfaces:**
- Consumes: Task 2 `SshStreamingCommandRunner`, Task 4 `InstallJobContext.appendLog`.
- Produces:
  - `typedef CliInstallOutputLine = void Function(String line);`
  - `CliInstallerService.install({..., CliInstallOutputLine? onOutputLine})`
  - `CliInstallerService.installAdapter({..., CliInstallOutputLine? onOutputLine})`

- [ ] **Step 1: Write the failing test**

No test is added to `cli_installer_service_test.dart`: the local streaming loop
only runs when `_localRunner` is the real `_runLocal` (it spawns processes), so
it cannot be unit-tested with an injected runner. Local streaming is verified in
the manual smoke step. The compile-time surface (`onOutputLine`) is driven by
the runner test below.

In `client/test/services/install/runners/cli_install_job_runner_test.dart`, update `_FakeCliInstallerService` and `_AdapterRecordingService` overrides to accept `CliInstallOutputLine? onOutputLine` and forward it in `_handler`. Add a new test:

```dart
    test('forwards ctx.appendLog as onOutputLine', () async {
      String? received;
      final service = _FakeCliInstallerService(({
        required cli,
        required mode,
        sshProfile,
        onProgress,
        isCancelled,
        onProcessStarted,
        onOutputLine,
      }) async {
        received = 'seen';
        onOutputLine?.call('hello');
        return const CliInstallResult(success: true, message: 'ok');
      });
      final runner = CliInstallJobRunner(installerFactory: () => service);
      final key = const InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: 'claude',
      );
      final lines = <String>[];

      await runner.run(
        _spec(key),
        InstallJobContext(appendLog: lines.add),
      );

      expect(received, 'seen');
      expect(lines, ['hello']);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_installer_service_test.dart test/services/install/runners/cli_install_job_runner_test.dart`
Expected: FAIL — `onOutputLine` not defined.

- [ ] **Step 3: Implement**

In `client/lib/services/cli/cli_installer_service.dart`:

1. Add near the top (after imports):

```dart
typedef CliInstallOutputLine = void Function(String line);
```

2. Constructor gains:

```dart
    SshStreamingInstallRunner? sshStreamingRunner,
```

with field:

```dart
  final SshStreamingInstallRunner? _sshStreamingRunner;
```

and initializer `_sshStreamingRunner = sshStreamingRunner,` plus a getter used by the host:

```dart
  SshStreamingInstallRunner? get _resolvedStreamingRunner {
    final injected = _sshStreamingRunner;
    if (injected != null) return injected;
    final factory = _sshClientFactory;
    if (factory == null) return null;
    return SshStreamingCommandRunner(
      startProcess: (profile, command) =>
          factory.startProcess(profile, command),
    ).run;
  }
```

Add `final SshClientFactory? _sshClientFactory;` set from the existing `sshClientFactory` parameter.

Add the typedef:

```dart
typedef SshStreamingInstallRunner = Future<CliInstallerCommandResult> Function(
  SshProfile profile,
  CliInstallerCommand command, {
  void Function(String line)? onOutput,
});
```

3. `install` and `installAdapter` gain `CliInstallOutputLine? onOutputLine,` and pass it into `_runInstall(... onOutputLine: onOutputLine)`.
4. `_runInstall` gains `CliInstallOutputLine? onOutputLine`, sets `_onOutputLine = onOutputLine;`, and clears it in `finally`.
5. Add field `CliInstallOutputLine? _onOutputLine;`.
6. `_runLocalTracked`:

```dart
    final useStreaming =
        (streamOutput || _onOutputLine != null) &&
        identical(_localRunner, _runLocal);
    if (useStreaming) {
      return _runLocalStreaming(
        command,
        onOutput: (line) {
          if (streamOutput) _report(phase, detail: line);
          _onOutputLine?.call(line);
        },
        onProcessStarted: _onProcessStarted,
      );
    }
```

7. `_CliInstallerHost.runSsh`:

```dart
  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) {
    final onOutput = _service._onOutputLine;
    final streaming = _service._resolvedStreamingRunner;
    if (onOutput == null || streaming == null) {
      return _service._sshRunner(profile, command);
    }
    return streaming(profile, command, onOutput: onOutput);
  }
```

Add imports for `SshStreamingCommandRunner` and `ProcessRunHandle` is not needed in this file.

In `client/lib/services/install/runners/cli_install_job_runner.dart`, pass the sink:

```dart
    final result = adapter != null
        ? await _installerFactory().installAdapter(
            installer: adapter,
            mode: mode,
            sshProfile: sshProfile,
            onProgress: onProgress,
            onOutputLine: ctx.appendLog,
            isCancelled: () => ctx.isCancelled,
            onProcessStarted: ctx.registerProcess,
          )
        : await _installerFactory().install(
            cli: cli!,
            mode: mode,
            sshProfile: sshProfile,
            onProgress: onProgress,
            onOutputLine: ctx.appendLog,
            isCancelled: () => ctx.isCancelled,
            onProcessStarted: ctx.registerProcess,
          );
```

Update the four test subclasses (`_FakeCliInstallerService`, `_AdapterRecordingService` in `cli_install_job_runner_test.dart`; `_AdapterInstallerService`, `_DelayedCliInstallerService` in `cli_config_section_test.dart`) so their `install`/`installAdapter` signatures include `CliInstallOutputLine? onOutputLine,`.

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli test/services/install test/pages/config/cli_config_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_installer_service.dart \
  client/lib/services/install/runners/cli_install_job_runner.dart \
  client/test/services/install/runners/cli_install_job_runner_test.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "feat(cli): stream install command output to the job log"
```

---

### Task 6: Toolchain (git) output

**Files:**
- Modify: `client/lib/services/cli/git_installer.dart`
- Modify: `client/lib/services/install/runners/toolchain_install_job_runner.dart`
- Test: `client/test/services/cli/git_installer_test.dart`
- Test: `client/test/services/install/runners/toolchain_install_job_runner_test.dart`

**Interfaces:**
- Produces: `GitInstaller({GitProcessRunner? processRunner, GitStreamingProcessRunner? streamingRunner, bool? isWindowsOverride})`, `GitInstaller.install({..., GitInstallOutputLine? onOutputLine})`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/cli/git_installer_test.dart`:

```dart
  test('forwards install command output through the streaming runner',
      () async {
    final lines = <String>[];
    final installer = GitInstaller(
      isWindowsOverride: true,
      processRunner: (exe, args) async => ProcessResult(0, 0, '', ''),
      streamingRunner: (exe, args, onOutput) async {
        onOutput('installing $exe');
        return ProcessResult(0, 0, '', '');
      },
    );

    final result = await installer.install(onOutputLine: lines.add);

    expect(result.success, isTrue);
    expect(lines, contains('installing winget'));
  });
```

In `client/test/services/install/runners/toolchain_install_job_runner_test.dart`, update the `installOverride` fakes to accept `onOutputLine`, and add:

```dart
    test('forwards ctx.appendLog to the installer', () async {
      final lines = <String>[];
      final runner = ToolchainInstallJobRunner(
        installOverride: ({
          onProgress,
          isCancelled,
          onOutputLine,
        }) async {
          onOutputLine?.call('git line');
          return const GitInstallResult.installed('/usr/bin/git');
        },
      );
      final key = InstallJobKeys.toolchain(
        'git',
        scope: const InstallJobScopeLocal(),
      );

      await runner.run(
        _spec(key),
        InstallJobContext(appendLog: lines.add),
      );

      expect(lines, ['git line']);
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/git_installer_test.dart test/services/install/runners/toolchain_install_job_runner_test.dart`
Expected: FAIL — new parameters not defined.

- [ ] **Step 3: Implement**

`client/lib/services/cli/git_installer.dart`:

```dart
typedef GitInstallOutputLine = void Function(String line);
typedef GitStreamingProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
  void Function(String line) onOutput,
);
```

Constructor:

```dart
  const GitInstaller({
    GitProcessRunner? processRunner,
    GitStreamingProcessRunner? streamingRunner,
    bool? isWindowsOverride,
  }) : _processRunner = processRunner ?? _defaultProcessRunner,
       _streamingRunner = streamingRunner,
       _isWindowsOverride = isWindowsOverride;

  final GitStreamingProcessRunner? _streamingRunner;
```

`install` gains `GitInstallOutputLine? onOutputLine` and forwards it to `_installWindows`/`_installMacOS`.

Replace the install command calls:

```dart
      final result = await _runInstallCommand(
        'winget',
        [
          'install',
          '--id',
          'Git.Git',
          '--exact',
          '--silent',
          '--accept-source-agreements',
          '--accept-package-agreements',
        ],
        onOutputLine,
      );
```

and

```dart
      final result = await _runInstallCommand(
        'brew',
        ['install', 'git'],
        onOutputLine,
      );
```

Add:

```dart
  Future<ProcessResult> _runInstallCommand(
    String executable,
    List<String> arguments,
    GitInstallOutputLine? onOutputLine,
  ) {
    final streaming = _streamingRunner;
    if (onOutputLine == null || streaming == null) {
      return _processRunner(executable, arguments);
    }
    return streaming(executable, arguments, onOutputLine);
  }
```

`client/lib/services/install/runners/toolchain_install_job_runner.dart`:

1. `GitInstallInvoke` gains `GitInstallOutputLine? onOutputLine,`.
2. `run` passes `onOutputLine: ctx.appendLog`.
3. `_install` forwards the parameter to the override or `_installerFactory().install(...)`.

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/git_installer_test.dart test/services/install/runners`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/git_installer.dart \
  client/lib/services/install/runners/toolchain_install_job_runner.dart \
  client/test/services/cli/git_installer_test.dart \
  client/test/services/install/runners/toolchain_install_job_runner_test.dart
git commit -m "feat(toolchain): stream git install output into the job log"
```

---

### Task 7: i18n keys

**Files:**
- Modify: `client/lib/i18n/log_en.i18n.json`
- Modify: `client/lib/i18n/log_zh.i18n.json`
- Generated: `client/lib/l10n/*` via `dart run slang`

- [ ] **Step 1: Add English keys**

Insert into `client/lib/i18n/log_en.i18n.json` (keep alphabetical order):

```json
  "installJobCopy": "Copy",
  "installJobEmpty": "No output yet.",
  "installJobPaused": "Paused",
  "installJobResume": "Follow",
  "installJobTitle": "Install log",
  "installJobTruncated": "Output truncated",
  "installJobUnavailable": "Log unavailable — the file was cleaned up.",
  "installJobViewLog": "View log",
```

- [ ] **Step 2: Add Chinese keys**

Insert into `client/lib/i18n/log_zh.i18n.json`:

```json
  "installJobCopy": "复制",
  "installJobEmpty": "暂无输出。",
  "installJobPaused": "已暂停",
  "installJobResume": "跟随",
  "installJobTitle": "安装日志",
  "installJobTruncated": "输出已截断",
  "installJobUnavailable": "日志不可用——文件已被清理。",
  "installJobViewLog": "查看日志",
```

- [ ] **Step 3: Regenerate**

Run: `cd client && dart run slang`
Expected: `client/lib/l10n/app_localizations*.dart` updated without errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/i18n/log_en.i18n.json client/lib/i18n/log_zh.i18n.json client/lib/l10n
git commit -m "feat(l10n): add install log dialog strings"
```

---

### Task 8: Log dialog and progress-dialog entry

**Files:**
- Create: `client/lib/widgets/install/job_log_dialog.dart`
- Modify: `client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart`
- Test: `client/test/widgets/install/job_log_dialog_test.dart`
- Test: `client/test/widgets/progress_activity/progress_activity_detail_dialog_test.dart`

**Interfaces:**
- Consumes: `JobLogStore` via `context.read<InstallJobRegistry>().logs`, `ProgressActivity.logToken`.
- Produces: `Future<void> showInstallJobLogDialog(BuildContext context, {required String token, required String title})`.

- [ ] **Step 1: Write the failing widget test**

Create `client/test/widgets/install/job_log_dialog_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/install/job_log_store.dart';
import 'package:teampilot/widgets/install/job_log_dialog.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_progress_cubit.dart';

const _key = InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: 'claude',
);

Widget _host(InstallJobRegistry registry, Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: RepositoryProvider<InstallJobRegistry>.value(
        value: registry,
        child: Scaffold(body: child),
      ),
    ),
  );
}

InstallJobRegistry _registry(JobLogStore store) =>
    InstallJobRegistry(progressCubit: TestProgressCubit(), logs: store);

void main() {
  testWidgets('streams live lines and keeps the final content', (tester) async {
    final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
    final registry = _registry(store);
    addTearDown(registry.dispose);
    final token = store.tokenFor(_key);
    final writer = store.begin(key: _key, title: 'Install Claude');
    writer.line('npm install claude');

    await tester.pumpWidget(_host(registry, const SizedBox.shrink()));
    unawaited(showInstallJobLogDialog(
      tester.element(find.byType(Scaffold)),
      token: token,
      title: 'Install Claude',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('npm install claude'), findsOneWidget);

    writer.line('added 1 package');
    await tester.pump();
    expect(find.textContaining('added 1 package'), findsOneWidget);

    await writer.close();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('added 1 package'), findsOneWidget);
  });

  testWidgets('shows the unavailable state for a missing log', (tester) async {
    final store = JobLogStore(appDataRoot: '/tp', fs: InMemoryFilesystem());
    final registry = _registry(store);
    addTearDown(registry.dispose);

    await tester.pumpWidget(_host(registry, const SizedBox.shrink()));
    unawaited(showInstallJobLogDialog(
      tester.element(find.byType(Scaffold)),
      token: 'missing',
      title: 'Install Claude',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Log unavailable — the file was cleaned up.'),
        findsOneWidget);
  });
}
```

Create `client/test/support/test_progress_cubit.dart`:

```dart
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';

class _NoopRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

class TestProgressCubit extends ProgressActivityCubit {
  TestProgressCubit() : super(historyRecorder: _NoopRecorder());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/install/job_log_dialog_test.dart`
Expected: FAIL — missing `job_log_dialog.dart` / `test_progress_cubit.dart`.

- [ ] **Step 3: Implement the dialog**

Create `client/lib/widgets/install/job_log_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/install/job_log_store.dart';

Future<void> showInstallJobLogDialog(
  BuildContext context, {
  required String token,
  required String title,
}) {
  final store = context.read<InstallJobRegistry>().logs;
  return showTpDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => JobLogDialog(
      token: token,
      title: title,
      store: store,
    ),
  );
}

class JobLogDialog extends StatefulWidget {
  const JobLogDialog({
    required this.token,
    required this.title,
    this.store,
    super.key,
  });

  final String token;
  final String title;
  final JobLogStore? store;

  @override
  State<JobLogDialog> createState() => _JobLogDialogState();
}

class _JobLogDialogState extends State<JobLogDialog> {
  final _scroll = ScrollController();
  final _lines = <String>[];
  StreamSubscription<String>? _sub;
  bool _following = true;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    if (store == null) {
      _unavailable = true;
      return;
    }
    if (!store.isLive(widget.token)) {
      unawaited(_loadStatic(store));
      return;
    }
    _sub = store.follow(widget.token).listen(
      (line) {
        if (!mounted) return;
        setState(() => _lines.add(line));
        _scrollToEnd();
      },
      onDone: () => unawaited(_loadStatic(store)),
      onError: (_) => unawaited(_loadStatic(store)),
    );
  }

  Future<void> _loadStatic(JobLogStore store) async {
    final lines = await store.read(widget.token);
    if (!mounted) return;
    setState(() {
      _lines
        ..clear()
        ..addAll(lines);
      _unavailable = lines.isEmpty;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n.log;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final logStyle = TextStyle(
      color: cs.onSurfaceVariant,
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.35,
    );

    return TpDialog(
      maxWidth: 760,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.installJobTitle,
            closeTooltip: context.l10n.windowControlClose,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          Text(widget.title, style: styles.mutedSm),
          const SizedBox(height: 8),
          Container(
            height: 420,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.all(8),
            child: _unavailable
                ? Center(
                    child: Text(l10n.installJobUnavailable, style: styles.mutedMd),
                  )
                : _lines.isEmpty
                    ? Center(
                        child: Text(l10n.installJobEmpty, style: styles.mutedMd),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: _lines.length,
                        itemBuilder: (context, index) => SelectableText(
                          _lines[index],
                          style: logStyle,
                        ),
                      ),
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: _lines.isEmpty
                    ? null
                    : () => Clipboard.setData(
                          ClipboardData(text: _lines.join('\n')),
                        ),
                child: Text(l10n.installJobCopy),
              ),
              if (!_unavailable)
                TextButton(
                  onPressed: () {
                    setState(() => _following = !_following);
                    if (_following) _scrollToEnd();
                  },
                  child: Text(
                    _following ? l10n.installJobPaused : l10n.installJobResume,
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.windowControlClose),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Also create `client/test/support/test_progress_cubit.dart` exactly as shown in Step 1.

- [ ] **Step 4: Add the progress-dialog button**

In `client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart`:

1. Import `../install/job_log_dialog.dart`.
2. Inside `_ProgressActivityDetailBody.build`, in `TpDialogActions.children`, before the Close button:

```dart
              if (activity.logToken != null)
                TextButton(
                  onPressed: () => showInstallJobLogDialog(
                    context,
                    token: activity.logToken!,
                    title: activity.title,
                  ),
                  child: Text(l10n.log.installJobViewLog),
                ),
```

- [ ] **Step 5: Add the progress-dialog test**

Append to `client/test/widgets/progress_activity/progress_activity_detail_dialog_test.dart`:

```dart
  testWidgets('shows the view log action only when logToken is set',
      (tester) async {
    final cubit = ProgressActivityCubit(historyRecorder: _FakeNotificationRecorder());
    addTearDown(cubit.close);
    final activity = ProgressActivity(
      id: 'a1',
      kind: ProgressActivityKind.cliProvision,
      title: 'Install Claude',
      phase: ProgressActivityPhase.running,
      logToken: 'tok-1',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
    );
    cubit.start(activity);
    await tester.pumpWidget(_host(cubit: cubit, child: const SizedBox()));
    unawaited(showProgressActivityDetailDialog(
      tester.element(find.byType(Scaffold)),
      activityId: 'a1',
    ));
    await tester.pumpAndSettle();

    expect(find.text('View log'), findsOneWidget);
  });
```

- [ ] **Step 6: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/widgets/install test/widgets/progress_activity`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/install/job_log_dialog.dart \
  client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart \
  client/test/support/test_progress_cubit.dart \
  client/test/widgets/install/job_log_dialog_test.dart \
  client/test/widgets/progress_activity/progress_activity_detail_dialog_test.dart
git commit -m "feat(install): add install log dialog and progress entry"
```

---

### Task 9: Notification payload branch and panel wiring

**Files:**
- Modify: `client/lib/services/notification/notification_center_open.dart`
- Modify: `client/lib/widgets/notification/notification_center_panel.dart`
- Test: `client/test/services/notification/notification_center_open_test.dart`

**Interfaces:**
- Produces: `openNotificationCenterItem({..., void Function(String token)? showInstallLog})`; payload prefix `install-log:`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/notification/notification_center_open_test.dart`:

```dart
  test('openNotificationCenterItem opens install logs instead of navigating',
      () async {
    final marked = <String>[];
    final navigated = <String>[];
    final logs = <String>[];
    final notification = AppNotification(
      id: 'n4',
      variant: TpToastVariant.error,
      title: 'Install Claude',
      message: 'Failed',
      createdAt: DateTime(2026, 7, 19),
      payload: 'install-log:tok-1',
    );

    await openNotificationCenterItem(
      notification: notification,
      markRead: (id) async => marked.add(id),
      go: navigated.add,
      showInstallLog: logs.add,
    );

    expect(marked, ['n4']);
    expect(logs, ['tok-1']);
    expect(navigated, isEmpty);
  });

  test('install-log payload without a callback is ignored', () async {
    final navigated = <String>[];
    final notification = AppNotification(
      id: 'n5',
      variant: TpToastVariant.success,
      message: 'Done',
      createdAt: DateTime(2026, 7, 19),
      payload: 'install-log:tok-1',
    );

    await openNotificationCenterItem(
      notification: notification,
      markRead: (id) async {},
      go: navigated.add,
    );

    expect(navigated, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/notification/notification_center_open_test.dart`
Expected: FAIL — `showInstallLog` not defined.

- [ ] **Step 3: Implement**

`client/lib/services/notification/notification_center_open.dart`:

```dart
import '../../models/app_notification.dart';

const installLogPayloadPrefix = 'install-log:';

/// Opens an in-app notification-center row: mark read, then deep-link if any.
Future<void> openNotificationCenterItem({
  required AppNotification notification,
  required Future<void> Function(String id) markRead,
  required void Function(String location) go,
  void Function(String token)? showInstallLog,
}) async {
  await markRead(notification.id);
  final location = notification.payload.trim();
  if (location.isEmpty) return;
  if (location.startsWith(installLogPayloadPrefix)) {
    final token = location.substring(installLogPayloadPrefix.length);
    if (token.isNotEmpty) showInstallLog?.call(token);
    return;
  }
  if (!location.startsWith('/home-v2/workspace/')) return;
  go(location);
}
```

`client/lib/widgets/notification/notification_center_panel.dart`: import
`../install/job_log_dialog.dart` and pass the callback:

```dart
                            unawaited(
                              openNotificationCenterItem(
                                notification: item,
                                markRead: notificationCubit.markRead,
                                go: (location) {
                                  onClose();
                                  appRouter.go(location);
                                },
                                showInstallLog: (token) {
                                  unawaited(
                                    showInstallJobLogDialog(
                                      context,
                                      token: token,
                                      title: item.title,
                                    ),
                                  );
                                  onClose();
                                },
                              ),
                            );
```

- [ ] **Step 4: Run tests**

Run: `cd client && dart run tool/run_tests.dart test/services/notification test/widgets/notification`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/notification/notification_center_open.dart \
  client/lib/widgets/notification/notification_center_panel.dart \
  client/test/services/notification/notification_center_open_test.dart
git commit -m "feat(notification): open install logs from the notification center"
```

---

### Task 10: Final verification

- [ ] **Step 1: Format changed files only, then analyze**

```bash
cd client && dart format \
  lib/services/install/job_log_store.dart \
  lib/services/install/install_job_registry.dart \
  lib/services/install/runners/cli_install_job_runner.dart \
  lib/services/install/runners/toolchain_install_job_runner.dart \
  lib/services/cli/cli_installer_service.dart \
  lib/services/cli/ssh_streaming_command_runner.dart \
  lib/services/cli/git_installer.dart \
  lib/services/notification/notification_center_open.dart \
  lib/models/progress_activity.dart \
  lib/models/install_job/install_job_context.dart \
  lib/cubits/progress_activity_cubit.dart \
  lib/widgets/install/job_log_dialog.dart \
  lib/widgets/progress_activity/progress_activity_detail_dialog.dart \
  lib/widgets/notification/notification_center_panel.dart \
  lib/app/bootstrap/install_wiring.dart \
  test/services/install/job_log_store_test.dart \
  test/services/cli/ssh_streaming_command_runner_test.dart \
  test/widgets/install/job_log_dialog_test.dart
cd client && flutter analyze
```

Expected: no analyzer issues.

- [ ] **Step 2: Run the covering test directories**

```bash
cd client && dart run tool/run_tests.dart \
  test/services/install test/services/cli test/services/notification \
  test/widgets/install test/widgets/progress_activity test/widgets/notification \
  test/cubits/progress_activity_cubit_test.dart test/pages/config/cli_config_section_test.dart
```

Expected: all PASS.

- [ ] **Step 3: Manual smoke (desktop, local install)**

Run the app, trigger a CLI install on the local machine from the config CLI card, confirm the "View log" button appears in the progress dialog, lines stream, and the success notification opens the same log.

- [ ] **Step 4: Manual smoke (remote install)**

With an SSH profile that lacks a CLI, trigger install from the machine readiness panel (`remote_cli_machine_readiness_panel.dart`). Confirm lines stream and the failure/success notification opens the log. If streaming SSH fails, the one-shot path is the rollback: passing `onOutputLine: null` restores `runOnStorage`.

- [ ] **Step 5: Report**

Summarize what changed, the verification commands run, and the smoke-test results.