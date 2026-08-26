# Login-shell PATH resolution for local PTY environments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Local PTY child processes get the user's real login-shell PATH, fixing `env: node: No such file or directory` (exit 127) for GUI-launched TeamPilot on macOS (and the same class of gap on Linux desktop launches).

**Architecture:** A one-shot resolver service runs `$SHELL|zsh|bash -ilc` at bootstrap to capture the login-shell PATH behind a marker and caches it; `PtyLaunchEnvironment.buildPtyEnvironment` merges it into local POSIX PTY child environments (preserving deliberate app prepends like skill-pack PATH exports), with a synchronous known-directories fallback when resolution has not completed or failed.

**Tech Stack:** Dart/Flutter (`dart:io` `Process.run`, latin1 decode, `package:meta/meta.dart` — direct dep already used by e.g. `app_update_install_job_runner.dart`), flutter_test. No new dependencies.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-26-login-shell-path-pty-environment-design.md`
- Scope gate: merge only when `inheritHostEnvironment == true` **and** (`Platform.isMacOS || Platform.isLinux`). Windows / SSH / WSL untouched.
- Never block startup or session connect on resolution: per-shell timeout 5 s; failures fall back silently.
- House style: static API + injectable process runner (mirror `client/lib/services/host/host_login_shell_lookup.dart` and `cli_tool_locator.dart`); no `print`; logging via `AppLogger` only.
- File size soft caps: services ≤ ~600 lines.
- Before claiming any task done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`.
- Full-suite verification (Task 3): `cd client && dart run tool/run_tests.dart`.
- Commit style: conventional commits (`feat: …`) as seen in `git log`.

---

### Task 1: `HostShellPathResolver` service

**Files:**
- Create: `client/lib/services/host/host_shell_path_resolver.dart`
- Test: `client/test/services/host/host_shell_path_resolver_test.dart`

**Interfaces:**
- Consumes: nothing new (`dart:io`, `package:meta`, existing `AppLogger`).
- Produces (Task 2 + Task 3 rely on these exact names):
  - `abstract final class HostShellPathResolver`
  - `static const String marker = '__TP_PATH__'`
  - `static const Duration defaultPerShellTimeout = Duration(seconds: 5)`
  - `typedef ShellPathProcessRunner = Future<ProcessResult> Function(String executable, List<String> arguments, {Encoding? stdoutEncoding, Encoding? stderrEncoding})`
  - `static List<String> shellCandidates()` — `[basename($SHELL)?, 'zsh', 'bash']`
  - `static String? parseMarkerOutput(Object? stdout)` — pure parser
  - `static Future<String?> resolve({ShellPathProcessRunner runner = defaultShellPathProcessRun, Duration timeout = defaultPerShellTimeout, bool? posixPlatformOverride})`
  - `static Future<void> warmup({ShellPathProcessRunner runner = defaultShellPathProcessRun})` — idempotent
  - `static String? get cachedPath`
  - `static List<String> fallbackCandidateDirs()` — `/opt/homebrew/bin`, `/usr/local/bin`, `$HOME/.local/bin` (existence NOT filtered here)
  - `@visibleForTesting static String Function()? debugShellOverride`
  - `@visibleForTesting static void debugSetCachedPath(String? path)`
  - `static void resetForTest()`

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/host/host_shell_path_resolver_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/host_shell_path_resolver.dart';

void main() {
  setUp(HostShellPathResolver.resetForTest);
  tearDown(HostShellPathResolver.resetForTest);

  ProcessResult ok(String stdout) => ProcessResult(0, 0, stdout, '');

  group('parseMarkerOutput', () {
    test('extracts PATH after marker', () {
      expect(
        HostShellPathResolver.parseMarkerOutput(
          '${HostShellPathResolver.marker}/usr/bin:/opt/homebrew/bin',
        ),
        '/usr/bin:/opt/homebrew/bin',
      );
    });

    test('uses content after the LAST marker and truncates at line breaks', () {
      const m = HostShellPathResolver.marker;
      final out =
          'nvm banner\r\n\$ PS1-active ${m}junk\nagain ${m}usr/relative\n'
          '$m/usr/bin:/bin tail';
      expect(HostShellPathResolver.parseMarkerOutput(out), '/usr/bin:/bin tail');
    });

    test('rejects missing marker, empty, and non-absolute results', () {
      const m = HostShellPathResolver.marker;
      expect(HostShellPathResolver.parseMarkerOutput('no marker'), isNull);
      expect(HostShellPathResolver.parseMarkerOutput('$m   '), isNull);
      expect(
        HostShellPathResolver.parseMarkerOutput('${m}relative/path'),
        isNull,
      );
    });
  });

  group('resolve', () {
    test('tries \$SHELL basename first, then zsh, then stops at first hit',
        () async {
      HostShellPathResolver.debugShellOverride = () => '/usr/local/bin/fish';
      final invoked = <String>[];
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          invoked.add(executable);
          if (executable == 'fish') {
            return Future.value(ok('fish noise')); // parses to null → continue
          }
          return Future.value(ok('${HostShellPathResolver.marker}/z/bin'));
        },
      );
      expect(result, '/z/bin');
      expect(invoked, ['fish', 'zsh']);
    });

    test('returns null when every shell times out', () async {
      // Override SHELL so candidates dedupe to exactly ['zsh', 'bash'],
      // regardless of the host environment.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) =>
            Completer<ProcessResult>().future,
      );
      expect(result, isNull);
    });

    test('falls through a hanging first shell to the next one', () async {
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh'; // → zsh,bash
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        timeout: const Duration(milliseconds: 10),
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          if (executable == 'zsh') return Completer<ProcessResult>().future;
          return Future.value(ok('${HostShellPathResolver.marker}/b/bin'));
        },
      );
      expect(result, '/b/bin');
    });

    test('caches success without re-running shells', () async {
      var calls = 0;
      await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('${HostShellPathResolver.marker}/c/bin'));
        },
      );
      final second = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('${HostShellPathResolver.marker}/other'));
        },
      );
      expect(second, '/c/bin');
      expect(calls, 1);
      expect(HostShellPathResolver.cachedPath, '/c/bin');
    });

    test('caches failure as null without retrying', () async {
      // Deterministic candidates: ['zsh', 'bash'] regardless of host SHELL.
      HostShellPathResolver.debugShellOverride = () => '/bin/zsh';
      var calls = 0;
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          return Future.value(ok('garbage without marker'));
        },
      );
      expect(result, isNull);
      expect(calls, 2); // zsh + bash both probed
      final again = await HostShellPathResolver.resolve(
        posixPlatformOverride: true,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) {
          calls++;
          fail('must not re-run');
        },
      );
      expect(again, isNull);
      expect(calls, 2); // cached failure → no additional probes
    });

    test('non-POSIX override short-circuits to null', () async {
      final result = await HostShellPathResolver.resolve(
        posixPlatformOverride: false,
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) =>
            fail('must not spawn'),
      );
      expect(result, isNull);
      expect(HostShellPathResolver.cachedPath, isNull);
    });
  });

  test('fallbackCandidateDirs includes homebrew, usr/local and ~/.local/bin',
      () {
    final dirs = HostShellPathResolver.fallbackCandidateDirs();
    expect(dirs.take(2), ['/opt/homebrew/bin', '/usr/local/bin']);
    expect(dirs.where((d) => d.endsWith('/.local/bin')), isNotEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/host/host_shell_path_resolver_test.dart`
Expected: FAIL — compile error, `host_shell_path_resolver.dart` does not exist.

- [ ] **Step 3: Implement the resolver**

Create `client/lib/services/host/host_shell_path_resolver.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../../utils/logging/logger.dart';

typedef ShellPathProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

Future<ProcessResult> defaultShellPathProcessRun(
  String executable,
  List<String> arguments, {
  Encoding? stdoutEncoding,
  Encoding? stderrEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    stdoutEncoding: stdoutEncoding ?? latin1,
    stderrEncoding: stderrEncoding ?? latin1,
  );
}

/// Resolves the user's login-shell PATH once per process so local PTY children
/// can run CLIs whose shebangs (`#!/usr/bin/env node`) need Homebrew /
/// version-manager / ~/.local/bin directories that GUI launches never inherit.
///
/// `-ilc` shells may print rc-file noise before command output (prompts, nvm
/// banners, escape sequences), so the PATH is captured behind a [marker] and
/// extracted from the last occurrence.
abstract final class HostShellPathResolver {
  HostShellPathResolver._();

  /// Output sentinel printed in front of the expanded `$PATH`.
  static const String marker = '__TP_PATH__';

  static const Duration defaultPerShellTimeout = Duration(seconds: 5);

  static const _fallbackShells = ['zsh', 'bash'];

  static bool _resolved = false;
  static String? _cachedPath;

  /// Test-only seam: overrides where `$SHELL` is read from.
  @visibleForTesting
  static String Function()? debugShellOverride;

  /// Test-only seam: forces/clears the cached resolution result.
  @visibleForTesting
  static void debugSetCachedPath(String? path) {
    _cachedPath = path;
    _resolved = true;
  }

  static String? get cachedPath => _cachedPath;

  static void resetForTest() {
    _resolved = false;
    _cachedPath = null;
    debugShellOverride = null;
  }

  static bool _isPosixDesktop() => Platform.isMacOS || Platform.isLinux;

  static List<String> shellCandidates() {
    final shell =
        debugShellOverride?.call() ?? Platform.environment['SHELL'] ?? '';
    final segments = shell.split('/');
    final basename = segments.isEmpty ? '' : segments.last.trim();
    return [
      if (basename.isNotEmpty) basename,
      ..._fallbackShells,
    ];
  }

  static List<String> fallbackCandidateDirs() {
    final home = Platform.environment['HOME']?.trim();
    return [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      if (home != null && home.isNotEmpty) '$home/.local/bin',
    ];
  }

  /// Extracts the PATH from shell stdout: everything after the LAST [marker],
  /// truncated at the first CR/LF (PATH cannot contain newlines), trimmed.
  /// Returns null when the marker is missing or the value is empty or has no
  /// absolute entry.
  static String? parseMarkerOutput(Object? stdout) {
    if (stdout is! String) return null;
    final index = stdout.lastIndexOf(marker);
    if (index < 0) return null;
    var value = stdout.substring(index + marker.length);
    final lineBreak = RegExp(r'[\r\n]').firstMatch(value);
    if (lineBreak != null) {
      value = value.substring(0, lineBreak.start);
    }
    value = value.trim();
    if (value.isEmpty) return null;
    final hasAbsoluteEntry = value.split(':').any((entry) => entry.startsWith('/'));
    return hasAbsoluteEntry ? value : null;
  }

  /// Kick off resolution once; later calls are no-ops.
  static Future<void> warmup({
    ShellPathProcessRunner runner = defaultShellPathProcessRun,
  }) {
    if (_resolved) return Future.value();
    return resolve(runner: runner);
  }

  static Future<String?> resolve({
    ShellPathProcessRunner runner = defaultShellPathProcessRun,
    Duration timeout = defaultPerShellTimeout,
    bool? posixPlatformOverride,
  }) async {
    if (_resolved) return _cachedPath;
    final posix = posixPlatformOverride ?? _isPosixDesktop();
    if (!posix) {
      _cachedPath = null;
      _resolved = true;
      return null;
    }
    String? resolved;
    for (final shell in shellCandidates()) {
      resolved = await _probeShell(shell, runner, timeout);
      if (resolved != null) break;
    }
    _cachedPath = resolved;
    _resolved = true;
    if (resolved == null) {
      appLogger.w(
        '[shell-path] login-shell PATH resolution failed; PTY spawns will '
        'append known candidate dirs instead',
      );
    } else {
      appLogger.i('[shell-path] login-shell PATH resolved');
    }
    return resolved;
  }

  static Future<String?> _probeShell(
    String shell,
    ShellPathProcessRunner runner,
    Duration timeout,
  ) async {
    try {
      // argv goes straight to `<shell> -c`. `$PATH` must expand in the CHILD
      // shell, so build the string via concatenation to dodge Dart `$`
      // interpolation: literal output is `printf "%s" "__TP_PATH__$PATH"`.
      final innerCommand = 'printf "%s" "$marker' + r'$PATH' + '"';
      final result = await runner(shell, [
        '-ilc',
        innerCommand,
      ]).timeout(timeout);
      if (result.exitCode != 0) return null;
      return parseMarkerOutput(result.stdout);
    } on TimeoutException {
      appLogger.w('[shell-path] $shell -ilc timed out');
      return null;
    } on Object catch (error) {
      appLogger.w('[shell-path] $shell -ilc failed: $error');
      return null;
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/host/host_shell_path_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/host/host_shell_path_resolver.dart client/test/services/host/host_shell_path_resolver_test.dart
git commit -m "feat(host): login-shell PATH resolver with marker parsing and caching"
```

---

### Task 2: Merge into `buildPtyEnvironment`

**Files:**
- Modify: `client/lib/services/terminal/pty_launch_environment.dart`
- Test: `client/test/services/terminal/pty_launch_environment_test.dart` (extend)

**Interfaces:**
- Consumes: `HostShellPathResolver.cachedPath`, `.fallbackCandidateDirs()`, `.resetForTest()`, `.debugSetCachedPath()` (Task 1).
- Produces:
  - `static void applyLocalLoginShellPath(Map<String, String> env, {required String? hostBasePath, required bool posixDesktop, List<String>? candidateDirs})` — public merge helper, direct-tested.
  - `buildPtyEnvironment` merges on POSIX when `inheritHostEnvironment: true`.

Merge algorithm (spec prefix-preservation semantics):

```
current   = env['PATH'] entries                     # prepends + host base
hostBase  = hostBasePath entries                    # sparse launchd/session PATH
prepends  = current entries minus any entry in hostBase (order preserved)
resolved  = cachedPath entries                      # may be null
fallback  = candidateDirs ?? resolver defaults, filtered to dirs that existSync()
result    = dedupe(prepends + (resolved ?? fallback) + hostBase leftovers)
```

- [ ] **Step 1: Write failing tests**

In `client/test/services/terminal/pty_launch_environment_test.dart`, add import:

```dart
import 'package:teampilot/services/host/host_shell_path_resolver.dart';
```

Append inside `main()`:

```dart
group('applyLocalLoginShellPath', () {
  late Directory tempDir;
  late String candidateA;
  late String candidateB;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tp_path_candidates');
    candidateA = '${tempDir.path}/a';
    candidateB = '${tempDir.path}/b';
    Directory(candidateA).createSync();
    Directory(candidateB).createSync();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
    HostShellPathResolver.resetForTest();
  });

  test('resolved PATH fills between prepends and host-base leftovers', () {
    HostShellPathResolver.debugSetCachedPath('/home/.nvm/bin:/sparse/bin');
    final env = {'PATH': '/skill/bin:/sparse/bin'};
    PtyLaunchEnvironment.applyLocalLoginShellPath(
      env,
      hostBasePath: '/sparse/bin',
      posixDesktop: true,
      candidateDirs: const [],
    );
    expect(env['PATH'], '/skill/bin:/home/.nvm/bin:/sparse/bin');
  });

  test('unresolved: appends existing missing candidates only', () {
    final env = {'PATH': '/sparse/bin:$candidateA'};
    PtyLaunchEnvironment.applyLocalLoginShellPath(
      env,
      hostBasePath: '/sparse/bin',
      posixDesktop: true,
      candidateDirs: [candidateA, candidateB],
    );
    expect(env['PATH'], '/sparse/bin:$candidateA:$candidateB');
  });

  test('skips candidates that do not exist', () {
    final env = {'PATH': '/sparse/bin'};
    PtyLaunchEnvironment.applyLocalLoginShellPath(
      env,
      hostBasePath: '/sparse/bin',
      posixDesktop: true,
      candidateDirs: ['/does/not/exist', candidateB],
    );
    expect(env['PATH'], '/sparse/bin:$candidateB');
  });

  test('creates PATH when env had none and host base empty', () {
    final env = <String, String>{};
    PtyLaunchEnvironment.applyLocalLoginShellPath(
      env,
      hostBasePath: '',
      posixDesktop: true,
      candidateDirs: [candidateA],
    );
    expect(env['PATH'], candidateA);
  });

  test('no-op when not a POSIX desktop', () {
    final env = {'PATH': '/keep'};
    PtyLaunchEnvironment.applyLocalLoginShellPath(
      env,
      hostBasePath: '/keep',
      posixDesktop: false,
      candidateDirs: [candidateA],
    );
    expect(env['PATH'], '/keep');
  });
});

test(
  'buildPtyEnvironment keeps inherited env untouched for SSH even when a '
  'login-shell PATH is cached',
  () {
    HostShellPathResolver.debugSetCachedPath('/nvm/bin');
    addTearDown(HostShellPathResolver.resetForTest);
    final env = PtyLaunchEnvironment.buildPtyEnvironment(
      const {'FOO': 'bar'},
      inheritHostEnvironment: false,
    );
    expect(env.containsKey('PATH'), isFalse);
  },
);

test(
  'buildPtyEnvironment applies login-shell PATH for local POSIX launches',
  () {
    HostShellPathResolver.debugSetCachedPath('/nvm/bin');
    addTearDown(HostShellPathResolver.resetForTest);
    final env = PtyLaunchEnvironment.buildPtyEnvironment(
      const {'FOO': 'bar'},
      inheritHostEnvironment: true,
    );
    // On macOS/Linux hosts the merged PATH must contain the resolved dir;
    // on other hosts this test would be skipped by the platform gate, so
    // guard explicitly.
    if (!Platform.isMacOS && !Platform.isLinux) return;
    expect(env['PATH'], contains('/nvm/bin'));
  },
);
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/terminal/pty_launch_environment_test.dart`
Expected: FAIL — `applyLocalLoginShellPath` undefined.

- [ ] **Step 3: Implement**

In `client/lib/services/terminal/pty_launch_environment.dart` change the import block to:

```dart
import 'dart:io';

import '../host/host_shell_path_resolver.dart';
```

Inside `PtyLaunchEnvironment` add:

```dart
/// Merges the user's login-shell PATH into a local PTY child environment.
///
/// Semantics (spec 2026-08-26): deliberate app prepends survive first, then
/// cached login-shell dirs fill in, then remaining host-base dirs. When no
/// resolution is cached yet, existing-but-missing fallback candidate dirs are
/// appended instead — cheap existsSync checks that rescue Homebrew-style
/// installs even if warmup lost the race with an instant reconnect.
static void applyLocalLoginShellPath(
  Map<String, String> env, {
  required String? hostBasePath,
  required bool posixDesktop,
  List<String>? candidateDirs,
}) {
  if (!posixDesktop) return;
  final currentEntries = (env['PATH'] ?? '')
      .split(':')
      .where((entry) => entry.isNotEmpty)
      .toList();
  final hostBaseEntries = (hostBasePath ?? '')
      .split(':')
      .where((entry) => entry.isNotEmpty)
      .toList();

  final result = <String>[
    ...currentEntries.where((entry) => !hostBaseEntries.contains(entry)),
  ];

  final resolved = HostShellPathResolver.cachedPath;
  if (resolved != null) {
    for (final entry in resolved.split(':')) {
      if (entry.isNotEmpty && !result.contains(entry)) result.add(entry);
    }
  } else {
    for (final dir
        in candidateDirs ?? HostShellPathResolver.fallbackCandidateDirs()) {
      if (!Directory(dir).existsSync()) continue;
      if (result.contains(dir)) continue;
      result.add(dir);
    }
  }

  for (final entry in hostBaseEntries) {
    if (entry.isEmpty || result.contains(entry)) continue;
    result.add(entry);
  }

  if (result.isNotEmpty) env['PATH'] = result.join(':');
}
```

At the end of `buildPtyEnvironment`, just before `return merged;`, insert:

```dart
if (inheritHostEnvironment &&
    (Platform.isMacOS || Platform.isLinux)) {
  applyLocalLoginShellPath(
    merged,
    hostBasePath: Platform.environment['PATH'],
    posixDesktop: true,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/terminal/pty_launch_environment_test.dart test/services/host/host_shell_path_resolver_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/terminal/pty_launch_environment.dart client/test/services/terminal/pty_launch_environment_test.dart
git commit -m "feat(terminal): merge login-shell PATH into local PTY environments"
```

---

### Task 3: Bootstrap wiring + full verification

**Files:**
- Modify: `client/lib/app/app_shell.dart` (~line 598, right after `boot('start');`)

**Interfaces:**
- Consumes: `HostShellPathResolver.warmup()` (Task 1).
- Produces: production trigger only; no signature changes downstream.

- [ ] **Step 1: Wire warmup**

Add import near the other service imports in `client/lib/app/app_shell.dart`:

```dart
import '../services/host/host_shell_path_resolver.dart';
```

In `buildAppShell`, immediately after `boot('start');` (app_shell.dart:598):

```dart
// Capture the user's real login-shell PATH early (POSIX desktops) so local
// PTY children see Homebrew/nvm/~/.local/bin despite sparse GUI PATH.
unawaited(HostShellPathResolver.warmup());
```

(`unawaited` is already imported in this file.)

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues.

- [ ] **Step 3: Targeted tests still green**

Run: `cd client && flutter test test/services/terminal/pty_launch_environment_test.dart test/services/host/host_shell_path_resolver_test.dart`
Expected: PASS.

- [ ] **Step 4: Full suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: all suites pass.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(app): warm up login-shell PATH resolution at bootstrap"
```

---

## Self-review notes

- Spec coverage: resolver (Task 1), merge with prefix preservation + sync fallback (Task 2), never-block wiring (Task 3), POSIX+inherit-only scope gates, SSH no-op regression test.
- Placeholder scan: all steps carry full code/commands; the two-step timeout scenario is spelled out as concrete replacement tests, not prose.
- Type consistency: `ShellPathProcessRunner` shape, `cachedPath`, `debugSetCachedPath(String?)`, `applyLocalLoginShellPath(env, hostBasePath:, posixDesktop:, candidateDirs:)` identical across Tasks 1–2.
- Known machine-dependence avoided: every merge test passes explicit `candidateDirs` backed by real temp dirs; no reliance on `/opt/homebrew/bin` existing on CI.
