# ACP Remote (SSH) Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a terminal-less ACP chat session run its agent on a remote SSH work target, instead of always spawning a local process.

**Architecture:** ACP already isolates the process behind `AcpTransport` (`lib/services/acp/acp_transport.dart`) and starts it through `AcpConnectionSpawner` (argv + env only). We add a second `AcpTransport` implementation over a single non-PTY SSH exec channel (`SSHClient.execute` → separated stdout/stderr + writable stdin), introduce an `AcpTransportStarter` seam so `productionAcpSpawner` can pick local-vs-SSH without touching the runtime/connection layers, and route personal ACP sessions to the SSH starter when the launch target uses SSH transport. Remote executable / env / config-dir values come from the existing PTY staging path (`SessionConnectOrchestrator.prepareSimpleConnect`), which already provisions the remote workspace and resolves the remote CLI path.

**Tech Stack:** Dart/Flutter, vendored `dartssh2` (`client/packages/dartssh2`), vendored `acpd` (`client/packages/acpd`), `RemoteCommandCodec` / `ChatSessionShellFactory.buildMemberRemoteCommand`.

---

## Scope And Assumptions

This plan is **Phase 1**. It was written without a live clarification round, so the assumptions below are explicit. Correct any that are wrong before executing.

- **In scope:** desktop SSH work targets (`RuntimeKind.ssh`), **personal (simple) ACP sessions** end-to-end. This is the case that is broken today: a personal Claude/Cursor/Codex/OpenCode session in an SSH workspace gets `acp: true` (see `resolveLaunchAcp` in `lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart:30`, which never inspects the target) and then `AcpRuntimeAttach.attachAcpRuntime` spawns the adapter **locally** with local paths (see `lib/services/chat/launch/connect/acp_runtime_attach.dart:88-125`).
- **Out of scope (separate follow-up plans):**
  - **Mixed-team remote seats.** `_memberAcpGates` (`lib/services/chat/launch/session/member_acp_stamp.dart:14`) keeps remote mixed members on the PTY terminal. Do not relax it here.
  - **MCP reachability on remote.** The ACP path currently forwards `127.0.0.1` MCP endpoints and omits `RemoteBusBinding`/`agentStatus` (`acp_runtime_attach.dart:409-450`); a remote agent cannot reach those. Remote personal sessions in Phase 1 carry **no** bus MCP, and `forwardSessionNewMcpServers` behavior is unchanged.
  - **Remote adapter install/locate for Claude/Codex.** On a remote target we deliberately stop passing the *local* boot-time adapter path and let the bare adapter name (`claude-agent-acp` / `codex-acp`) resolve on the remote `PATH` (the managed Node path + `~/.local/bin` are exported by the remote command builder). Remote adapter path override UI is follow-up work.
  - **Android / Termux.** `resolveLaunchAcp` already returns false on Android, so Termux stays disabled. Do not change that.
  - **SSH reconnect for an in-flight ACP seat.** `SshProfileConnectionCoordinator.sessionReconnectSignals` wiring for ACP is follow-up work.

## Global Constraints

- **Never run `flutter test` directly.** Use `cd client && dart run tool/run_tests.dart <paths/options>`.
- **Test loop:** inner loop = `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` (from `client/`); verify one file with `dart run tool/run_tests.dart <path>`; run the full suite once before claiming done.
- **Layering:** `services/acp/` stays CLI-agnostic (no `CliTool`/registry imports). The registry → acp direction is one-way. New SSH *wiring* that needs `CliTool`/chat-launch helpers goes under `cubits/session/acp/` (next to `acp_launch_wiring.dart`).
- **Never merge stderr into stdout** for an ACP transport (opposite of `SshPtyTransport`).
- **Never use `Directory.current`** for workspace/app-data roots; paths come from injected `HomeStorage` / `RuntimeContextRegistry`.
- **Logging:** diagnostics via `AppLogger`, user errors via l10n. No `print`.
- **l10n:** edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only.
- **Env empty-value semantics:** `AcpProcessTransport` drops empty env values (`mergeAcpProcessEnvironment`) so `ANTHROPIC_API_KEY=''` becomes *unset* (Claude treats a set-but-empty key as API-key mode → "Not logged in"). The remote command builder exports whatever it is given, so the SSH transport **must** drop empty values before building the remote command.

---

## File Structure

**Create:**
- `client/lib/services/acp/acp_ssh_transport.dart` — `AcpSshChannel` seam, `DartSsh2AcpChannel` adapter over `SSHSession`, `AcpSshTransport`.
- `client/test/services/acp/acp_ssh_transport_test.dart`
- `client/lib/cubits/session/acp/acp_transport_wiring.dart` — `AcpTransportStarter` typedef, `localAcpTransportStarter`, `sshAcpTransportStarter`, `buildAcpRemoteCommand`, `AcpSshChannelOpener`, `AcpSshLaunch`, `AcpSshLaunchFactory`, `acpStarterForTarget`.
- `client/test/cubits/session/acp/acp_transport_wiring_test.dart`

**Modify:**
- `client/lib/services/ssh/ssh_member_session.dart` — add `openExec`.
- `client/lib/cubits/session/acp/acp_launch_wiring.dart` — `productionAcpSpawner` takes an optional `AcpTransportStarter`.
- `client/lib/services/chat/launch/connect/acp_launch_environment.dart` — add `AcpPreparedSimpleConnect` + `selectAcpRemoteLaunch`.
- `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` — remote branch for personal attach; `_cubit` takes `launchTarget` + `AcpSshLaunch`.
- `client/lib/services/chat/launch/session_launch_service.dart` — new test seams `prepareAcpRemoteStaging`, `prepareAcpSshLaunch`.
- `client/test/services/chat/launch/acp_launch_environment_test.dart` — tests for `selectAcpRemoteLaunch`.
- `client/test/cubits/session/acp/acp_launch_wiring_test.dart` — test injected starter.
- `docs/ARCHITECTURE.md` — note the ACP remote transport seam (Task 7).

---

### Task 1: SSH ACP transport

**Files:**
- Create: `client/lib/services/acp/acp_ssh_transport.dart`
- Test: `client/test/services/acp/acp_ssh_transport_test.dart`

**Interfaces:**
- Consumes: `AcpTransport` from `lib/services/acp/acp_transport.dart` (`Stream<Uint8List> get input`, `void write(String frame)`, `Stream<List<int>> get stderr`, `Future<void> close()`, `bool get isClosed`); vendored `SSHSession` (separate `stdout`/`stderr`, writable `stdin`, `done`, `exitCode`, `kill(SSHSignal)`, `close()`).
- Produces:
  - `abstract interface class AcpSshChannel` with `Stream<Uint8List> get stdout`, `Stream<Uint8List> get stderr`, `Future<int> get exitCode`, `void write(Uint8List data)`, `Future<void> closeStdin()`, `void kill()`, `void dispose()`.
  - `class DartSsh2AcpChannel implements AcpSshChannel` (constructor `DartSsh2AcpChannel(SSHSession session)`).
  - `class AcpSshTransport implements AcpTransport` with `AcpSshTransport({required AcpSshChannel channel, void Function(List<int>)? onStderr, Duration gracefulShutdownTimeout})` and `Future<int> get processExitCode`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/acp/acp_ssh_transport_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_ssh_transport.dart';

class _FakeAcpSshChannel implements AcpSshChannel {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final exitCompleter = Completer<int>();
  final written = <String>[];
  bool stdinClosed = false;
  bool killed = false;
  bool disposed = false;

  /// When false, [kill] does NOT complete the exit future — models a remote
  /// process that ignores the graceful path until SIGKILL.
  bool exitOnKill = true;

  @override
  Stream<Uint8List> get stdout => stdoutController.stream;

  @override
  Stream<Uint8List> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void write(Uint8List data) => written.add(utf8.decode(data));

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  void kill() {
    killed = true;
    if (exitOnKill && !exitCompleter.isCompleted) exitCompleter.complete(137);
  }

  @override
  void dispose() => disposed = true;

  void finish(int code) {
    if (!exitCompleter.isCompleted) exitCompleter.complete(code);
  }
}

void main() {
  test('write appends a newline-terminated frame', () {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    transport.write('{"jsonrpc":"2.0"}');
    expect(channel.written, ['{"jsonrpc":"2.0"}\n']);
  });

  test('input forwards remote stdout bytes', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    final seen = <int>[];
    final sub = transport.input.listen(seen.addAll);
    channel.stdoutController.add(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [1, 2, 3]);
    await sub.cancel();
  });

  test('stderr stays separate and reaches onStderr and the stderr stream',
      () async {
    final channel = _FakeAcpSshChannel();
    final onStderr = <int>[];
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: onStderr.addAll,
    );
    final seenStderr = <int>[];
    final sub = transport.stderr.listen(seenStderr.addAll);
    channel.stderrController.add(Uint8List.fromList([9, 8]));
    await Future<void>.delayed(Duration.zero);
    expect(onStderr, [9, 8]);
    expect(seenStderr, [9, 8]);
    await sub.cancel();
  });

  test('close sends stdin EOF, waits for exit, disposes without killing', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: null,
      gracefulShutdownTimeout: const Duration(milliseconds: 200),
    );
    final closing = transport.close();
    channel.finish(0);
    await closing;
    expect(channel.stdinClosed, isTrue);
    expect(channel.killed, isFalse);
    expect(channel.disposed, isTrue);
    expect(transport.isClosed, isTrue);
  });

  test('close escalates to kill when the remote ignores EOF', () async {
    final channel = _FakeAcpSshChannel()..exitOnKill = false;
    final transport = AcpSshTransport(
      channel: channel,
      onStderr: null,
      gracefulShutdownTimeout: const Duration(milliseconds: 20),
    );
    final closing = transport.close();
    // First timeout fires, kill() runs and (exitOnKill=false) does not finish.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    channel.finish(137);
    await closing;
    expect(channel.killed, isTrue);
    expect(channel.disposed, isTrue);
  });

  test('write after close is a no-op', () async {
    final channel = _FakeAcpSshChannel();
    final transport = AcpSshTransport(channel: channel, onStderr: null);
    final closing = transport.close();
    channel.finish(0);
    await closing;
    transport.write('late');
    expect(channel.written, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_ssh_transport_test.dart`
Expected: FAIL — `acp_ssh_transport.dart` does not exist / `AcpSshChannel` undefined.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/acp/acp_ssh_transport.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'acp_transport.dart';

/// Narrow seam over one non-PTY SSH exec channel.
///
/// Keeps [AcpSshTransport] unit-testable without a real sshd; production wires
/// [DartSsh2AcpChannel] over a vendored dartssh2 [SSHSession].
abstract interface class AcpSshChannel {
  /// Remote stdout (NDJSON bytes). Never merged with stderr.
  Stream<Uint8List> get stdout;

  /// Remote stderr, kept separate from [stdout].
  Stream<Uint8List> get stderr;

  /// Completes with the remote exit code once the command finishes.
  Future<int> get exitCode;

  /// Writes one chunk to the remote stdin.
  void write(Uint8List data);

  /// Sends EOF on stdin so the agent can shut down cleanly.
  Future<void> closeStdin();

  /// Hard-kills the remote command.
  void kill();

  /// Releases local channel resources.
  void dispose();
}

/// [AcpSshChannel] over a vendored dartssh2 [SSHSession].
///
/// A bare [SSHSession] from `SSHClient.execute` already separates stdout and
/// stderr and exposes a writable stdin, which is exactly the ACP framing shape.
final class DartSsh2AcpChannel implements AcpSshChannel {
  DartSsh2AcpChannel(this._session);

  final SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  Future<int> get exitCode => _session.done.then((_) => _session.exitCode ?? 0);

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  Future<void> closeStdin() => _session.stdin.close();

  @override
  void kill() => _session.kill(SSHSignal.KILL);

  @override
  void dispose() => _session.close();
}

/// [AcpTransport] over an SSH exec channel.
///
/// Mirrors `AcpProcessTransport`: no PTY, stdout carries NDJSON frames, stderr
/// stays separate, and [close] goes EOF → SIGKILL. [processExitCode] feeds the
/// spawner's handshake race so a rejected flag / not-logged-in agent is
/// classified the same way as locally.
class AcpSshTransport implements AcpTransport {
  AcpSshTransport({
    required AcpSshChannel channel,
    required void Function(List<int>)? onStderr,
    this.gracefulShutdownTimeout = const Duration(seconds: 5),
  }) : _channel = channel {
    _stderrController = StreamController<List<int>>.broadcast();
    _stderrSubscription = _channel.stderr.listen(
      (chunk) {
        onStderr?.call(chunk);
        _stderrController.add(chunk);
      },
      onError: _stderrController.addError,
      onDone: _stderrController.close,
    );
  }

  /// How long to wait after EOF before escalating to [AcpSshChannel.kill].
  final Duration gracefulShutdownTimeout;

  final AcpSshChannel _channel;
  late final StreamController<List<int>> _stderrController;
  late final StreamSubscription<List<int>> _stderrSubscription;
  bool _closed = false;

  @override
  Stream<Uint8List> get input => _channel.stdout;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  /// Remote exit code; consumed by the spawner's handshake race.
  Future<int> get processExitCode => _channel.exitCode;

  @override
  bool get isClosed => _closed;

  @override
  void write(String frame) {
    if (_closed) return;
    _channel.write(Uint8List.fromList(utf8.encode('$frame\n')));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    try {
      await _channel.closeStdin();
    } on Object {
      // stdin may already be closed; best-effort during shutdown.
    }

    var exited = true;
    try {
      await _channel.exitCode.timeout(gracefulShutdownTimeout);
    } on TimeoutException {
      exited = false;
    }

    if (!exited) {
      _channel.kill();
      try {
        await _channel.exitCode.timeout(gracefulShutdownTimeout);
      } on TimeoutException {
        // SIGKILL cannot be ignored by a live process; if this fires the
        // remote process is already gone.
      }
    }

    _channel.dispose();
    await _stderrSubscription.cancel();
    if (!_stderrController.isClosed) {
      await _stderrController.close();
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_ssh_transport_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_ssh_transport.dart client/test/services/acp/acp_ssh_transport_test.dart
git commit -m "feat(acp): add SSH exec transport for ACP agents"
```

---

### Task 2: `SshMemberSession.openExec`

**Files:**
- Modify: `client/lib/services/ssh/ssh_member_session.dart` (add a method after `openPty`, around line 64)

**Interfaces:**
- Consumes: `SshMemberSession.client` (raw `SSHClient`), vendored `SSHClient.execute(String command)` → `Future<SSHSession>`.
- Produces: `Future<SSHSession> SshMemberSession.openExec(String command)`.

This is a thin delegation; it is exercised indirectly by `smoke` in Task 4's integration note rather than a dedicated unit test (faking `SSHSession` requires implementing ~12 members). Keep it minimal.

- [ ] **Step 1: Add the method**

In `client/lib/services/ssh/ssh_member_session.dart`, after `openPty` (ends line 64), insert:

```dart
  /// Opens a non-PTY exec channel: separated stdout/stderr and a writable
  /// stdin. Used by the remote ACP transport, which must NOT use a PTY (a PTY
  /// merges stderr into stdout and echoes, both of which corrupt NDJSON).
  Future<SSHSession> openExec(String command) => client.execute(command);
```

- [ ] **Step 2: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/ssh/ssh_member_session.dart
git commit -m "feat(ssh): add non-PTY openExec to SshMemberSession"
```

---

### Task 3: `AcpTransportStarter` seam + local starter

**Files:**
- Create: `client/lib/cubits/session/acp/acp_transport_wiring.dart`
- Modify: `client/lib/cubits/session/acp/acp_launch_wiring.dart:90-159` (`productionAcpSpawner`)
- Test: `client/test/cubits/session/acp/acp_launch_wiring_test.dart`

**Interfaces:**
- Consumes: `AcpProcessTransport.start({executable, args, environment, workingDirectory, onStderr})`; `AcpAgentConnection({transport, logger, translator, processExitCode})`; `AcpTransport`.
- Produces:
  - `typedef AcpStartedTransport = ({AcpTransport transport, Future<int>? processExitCode})`.
  - `typedef AcpTransportStarter = Future<AcpStartedTransport> Function({required List<String> argv, required Map<String, String> env, required String workingDirectory, void Function(List<int>)? onStderr})`.
  - `AcpTransportStarter localAcpTransportStarter()`.
  - `productionAcpSpawner(..., AcpTransportStarter? transportStarter)` — `null` means `localAcpTransportStarter()` (unchanged local behavior).

- [ ] **Step 1: Write the failing test**

Append to `client/test/cubits/session/acp/acp_launch_wiring_test.dart` (add imports for `dart:typed_data`, `package:teampilot/cubits/session/acp/acp_transport_wiring.dart`, `package:teampilot/services/acp/acp_frame_logger.dart`, `package:teampilot/services/acp/acp_transport.dart`, `package:teampilot/services/cli/registry/cli_tool_registry.dart`, `package:teampilot/models/team_config.dart`):

```dart
class _SilentTransport implements AcpTransport {
  final _input = StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List> get input => _input.stream;
  @override
  void write(String frame) {}
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<void> close() async {
    if (!_input.isClosed) await _input.close();
  }

  @override
  bool get isClosed => _input.isClosed;
}
```

```dart
  test(
    'productionAcpSpawner uses the injected starter and classifies its exit',
    () async {
      List<String>? seenArgv;
      String? seenWorkingDirectory;
      final exit = Completer<int>();
      final starter = ({
        required List<String> argv,
        required Map<String, String> env,
        required String workingDirectory,
        void Function(List<int>)? onStderr,
      }) async {
        seenArgv = argv;
        seenWorkingDirectory = workingDirectory;
        return (transport: _SilentTransport(), processExitCode: exit.future);
      };

      final spawner = productionAcpSpawner(
        registry: CliToolRegistry.builtIn(),
        tool: CliTool.opencode,
        workingDirectory: '/remote/work',
        logger: AcpFrameLogger(),
        transportStarter: starter,
        handshakeTimeout: const Duration(milliseconds: 200),
      );

      final launched = spawner(['opencode', 'acp'], const {});
      exit.complete(127);
      await expectLater(launched, throwsA(isA<AcpFlagRejected>()));
      expect(seenArgv, ['opencode', 'acp']);
      expect(seenWorkingDirectory, '/remote/work');
    },
  );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart --plain-name "injected starter"`
Expected: FAIL — `transportStarter` is not a named parameter of `productionAcpSpawner`.

- [ ] **Step 3: Add the starter seam**

Create `client/lib/cubits/session/acp/acp_transport_wiring.dart`:

```dart
import '../../../services/acp/acp_process_transport.dart';
import '../../../services/acp/acp_transport.dart';

/// One started ACP transport plus the exit future the handshake race needs.
///
/// [processExitCode] is null for transports with no process-like exit status.
typedef AcpStartedTransport = ({
  AcpTransport transport,
  Future<int>? processExitCode,
});

/// Starts one ACP agent transport for an argv + env candidate.
///
/// `workingDirectory` (and, for SSH, the member session) is captured by the
/// starter closure — the same shape as `productionAcpSpawner`, which captures
/// cwd too. This is the local-vs-remote fork point.
typedef AcpTransportStarter =
    Future<AcpStartedTransport> Function({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    });

/// Local desktop process transport (unchanged pre-remote behavior).
AcpTransportStarter localAcpTransportStarter() =>
    ({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    }) async {
      final transport = await AcpProcessTransport.start(
        executable: argv.first,
        args: argv.skip(1).toList(),
        environment: env,
        workingDirectory: workingDirectory,
        onStderr: onStderr,
      );
      return (
        transport: transport,
        processExitCode: transport.processExitCode,
      );
    };
```

- [ ] **Step 4: Use the starter inside `productionAcpSpawner`**

In `client/lib/cubits/session/acp/acp_launch_wiring.dart`:

Add the import:
```dart
import 'acp_transport_wiring.dart';
```

Replace the `productionAcpSpawner` signature and body (currently lines 90-159) with:

```dart
AcpConnectionSpawner productionAcpSpawner({
  required CliToolRegistry registry,
  required CliTool tool,
  required String workingDirectory,
  required AcpFrameLogger logger,
  AcpTransportStarter? transportStarter,
  String clientName = 'teampilot',
  String clientVersion = '1.0.0',
  Duration handshakeTimeout = const Duration(seconds: 30),
}) {
  final starter = transportStarter ?? localAcpTransportStarter();
  final translator =
      registry.capability<AcpCapability>(tool)?.translator ??
      const _NoopAcpTranslator();
  return (argv, env) async {
    final started = await starter(
      argv: argv,
      env: env,
      workingDirectory: workingDirectory,
      onStderr: (chunk) {
        if (chunk.isEmpty) return;
        AppLogger.instance.d(
          '[acp-stderr] ${utf8.decode(chunk, allowMalformed: true)}',
        );
      },
    );
    // Observed by the runtime's agent-exit watcher after a successful start
    // (mid-session crash → inline system message). Futures are multicast, so
    // sharing this with the handshake race below is safe.
    final processExitCode = started.processExitCode;
    final connection = AcpAgentConnection(
      transport: started.transport,
      logger: logger,
      translator: translator,
      processExitCode: processExitCode,
    );
    try {
      final authenticateMethodId = await spawnAuthenticateMethodId(
        registry.capability<AcpCapability>(tool),
        env,
      );
      // Initialize race uses authenticating: false — an old CLI dying on
      // the flag is still AcpFlagRejected, not not-logged-in.
      await raceHandshake(
        connection.initialize(
          clientName: clientName,
          clientVersion: clientVersion,
          timeout: handshakeTimeout,
        ),
        processExitCode,
        authenticating: false,
      );
      if (authenticateMethodId != null) {
        // Authenticate race uses authenticating: true — exit after
        // initialize succeeded is not-logged-in, not a bad flag.
        await raceHandshake(
          connection.authenticate(
            authenticateMethodId,
            timeout: handshakeTimeout,
          ),
          processExitCode,
          authenticating: true,
        );
      }
      return connection;
    } on Object {
      await connection.dispose();
      rethrow;
    }
  };
}
```

Remove the now-unused `import '../../../services/acp/acp_process_transport.dart';` from `acp_launch_wiring.dart`.

Note: `raceHandshake`'s `processExitCode` parameter is `Future<int>` (not nullable). Since `productionAcpSpawner` always wires a starter whose `processExitCode` is non-null for both local and SSH, keep the existing signature. If `started.processExitCode` is ever null, substitute a never-completing future:

```dart
    final processExitCode = started.processExitCode ?? Completer<int>().future;
```

Use that form (add `import 'dart:async';` if not present).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_launch_wiring_test.dart`
Expected: PASS (all tests, including the new one).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session/acp/acp_transport_wiring.dart client/lib/cubits/session/acp/acp_launch_wiring.dart client/test/cubits/session/acp/acp_launch_wiring_test.dart
git commit -m "refactor(acp): extract AcpTransportStarter seam from productionAcpSpawner"
```

---

### Task 4: SSH starter + remote command building

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_transport_wiring.dart`
- Test: `client/test/cubits/session/acp/acp_transport_wiring_test.dart`

**Interfaces:**
- Consumes: `ChatSessionShellFactory.buildMemberRemoteCommand({required SshProfile profile, required String executable, required List<String> arguments, required String remoteWorkingDirectory, required Map<String, String>? environment, required bool useLoginShell})` (static, `lib/services/chat/launch/connect/chat_session_shell_factory.dart:181`); `SshProfile` (`lib/models/ssh_profile.dart`); `AcpSshTransport` / `DartSsh2AcpChannel` (Task 1).
- Produces:
  - `String buildAcpRemoteCommand({required SshProfile profile, required List<String> argv, required String workingDirectory, required Map<String, String> env})` — drops empty env values.
  - `typedef AcpSshChannelOpener = Future<AcpSshChannel> Function(String command)`.
  - `AcpTransportStarter sshAcpTransportStarter({required SshProfile profile, required AcpSshChannelOpener openChannel})`.
  - `typedef AcpSshLaunch = ({SshProfile profile, AcpSshChannelOpener openChannel})`.
  - `typedef AcpSshLaunchFactory = AcpSshLaunch Function({required AppSession session, required RuntimeTarget launchTarget})`.
  - `AcpTransportStarter? acpStarterForTarget({required RuntimeTarget launchTarget, AcpSshLaunch? sshLaunch})`.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/session/acp/acp_transport_wiring_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_transport_wiring.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/acp/acp_ssh_transport.dart';

class _FakeChannel implements AcpSshChannel {
  final exit = Completer<int>();
  @override
  Stream<Uint8List> get stdout => const Stream.empty();
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => exit.future;
  @override
  void write(Uint8List data) {}
  @override
  Future<void> closeStdin() async {}
  @override
  void kill() {}
  @override
  void dispose() {}
}

const _profile = SshProfile(
  id: 'p1',
  name: 'host',
  host: 'host',
  username: 'u',
  authType: SshAuthType.password,
);

void main() {
  test('buildAcpRemoteCommand drops empty env values', () {
    final command = buildAcpRemoteCommand(
      profile: _profile,
      argv: const ['opencode', 'acp'],
      workingDirectory: '/work/proj',
      env: const {
        'HOME': '/home/u',
        'ANTHROPIC_API_KEY': '',
      },
    );
    expect(command, contains('opencode'));
    expect(command, contains('/work/proj'));
    expect(command, isNot(contains('ANTHROPIC_API_KEY')));
    expect(command, contains('HOME'));
  });

  test('sshAcpTransportStarter opens a channel for the built command', () async {
    String? seenCommand;
    final channel = _FakeChannel();
    final starter = sshAcpTransportStarter(
      profile: _profile,
      openChannel: (command) async {
        seenCommand = command;
        return channel;
      },
    );

    final started = await starter(
      argv: const ['opencode', 'acp'],
      env: const {},
      workingDirectory: '/work/proj',
      onStderr: null,
    );

    expect(seenCommand, isNotNull);
    expect(seenCommand, contains('opencode'));
    expect(started.transport, isA<AcpSshTransport>());
    // The exit future is wired to the channel, not completed yet.
    // (`AcpStartedTransport.processExitCode` is nullable, hence the `!`.)
    expect(started.processExitCode, isNotNull);
    expect(
      await started.processExitCode!.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => -1,
      ),
      -1,
    );
    channel.exit.complete(0);
    expect(await started.processExitCode, 0);
  });

  test('acpStarterForTarget is null for a local target', () {
    expect(
      acpStarterForTarget(
        launchTarget: RuntimeTarget.local(),
        sshLaunch: null,
      ),
      isNull,
    );
  });

  test('acpStarterForTarget throws when a remote target has no SSH launch', () {
    expect(
      () => acpStarterForTarget(
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        sshLaunch: null,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('acpStarterForTarget returns an SSH starter for a remote target', () {
    final starter = acpStarterForTarget(
      launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
      sshLaunch: (profile: _profile, openChannel: (_) async => _FakeChannel()),
    );
    expect(starter, isNotNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_transport_wiring_test.dart`
Expected: FAIL — `buildAcpRemoteCommand`, `sshAcpTransportStarter`, `acpStarterForTarget` undefined.

- [ ] **Step 3: Implement**

Append to `client/lib/cubits/session/acp/acp_transport_wiring.dart` (and add imports `dart:typed_data` is not needed; add `../../../models/app_session.dart`, `../../../models/runtime_target.dart`, `../../../models/ssh_profile.dart`, `../../../services/acp/acp_ssh_transport.dart`, `../../../services/chat/launch/connect/chat_session_shell_factory.dart`):

```dart
/// Builds the remote shell command for one ACP argv candidate.
///
/// Empty env values are dropped: the local transport removes them so a
/// set-but-empty `ANTHROPIC_API_KEY` is *unset*, but the remote command builder
/// exports whatever it is given. Passing `K=''` would flip Claude into API-key
/// mode with no key ("Not logged in"), so filter first.
///
/// No login shell: `.bashrc` banners would corrupt the NDJSON stdout channel.
/// The legacy codec still exports the managed Node path and `~/.local/bin`,
/// which covers the agent/adapter binary.
String buildAcpRemoteCommand({
  required SshProfile profile,
  required List<String> argv,
  required String workingDirectory,
  required Map<String, String> env,
}) {
  final cleaned = <String, String>{
    for (final entry in env.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };
  return ChatSessionShellFactory.buildMemberRemoteCommand(
    profile: profile,
    executable: argv.first,
    arguments: argv.skip(1).toList(),
    remoteWorkingDirectory: workingDirectory,
    environment: cleaned.isEmpty ? null : cleaned,
    useLoginShell: false,
  );
}

/// Opens one SSH exec channel for a command. Production wraps
/// `SshMemberSession.openExec` in [DartSsh2AcpChannel]; tests inject a fake.
typedef AcpSshChannelOpener = Future<AcpSshChannel> Function(String command);

/// Remote transport over one SSH member session.
AcpTransportStarter sshAcpTransportStarter({
  required SshProfile profile,
  required AcpSshChannelOpener openChannel,
}) =>
    ({
      required List<String> argv,
      required Map<String, String> env,
      required String workingDirectory,
      void Function(List<int>)? onStderr,
    }) async {
      final command = buildAcpRemoteCommand(
        profile: profile,
        argv: argv,
        workingDirectory: workingDirectory,
        env: env,
      );
      final channel = await openChannel(command);
      final transport = AcpSshTransport(channel: channel, onStderr: onStderr);
      return (
        transport: transport,
        processExitCode: transport.processExitCode,
      );
    };

/// Everything the remote ACP starter needs: the SSH profile (for command
/// encoding) and a lazy channel opener.
typedef AcpSshLaunch = ({
  SshProfile profile,
  AcpSshChannelOpener openChannel,
});

/// Builds one [AcpSshLaunch] for a session + target. Production opens (and
/// stores on the tab) the member SSH session; tests inject a fake.
typedef AcpSshLaunchFactory = AcpSshLaunch Function({
  required AppSession session,
  required RuntimeTarget launchTarget,
});

/// Null → the spawner's local process starter. Non-null → the SSH starter.
///
/// A remote target without an [AcpSshLaunch] is a wiring bug, not a fallback:
/// failing loudly avoids silently spawning a local process for a remote
/// workspace (the pre-Phase-1 behavior).
AcpTransportStarter? acpStarterForTarget({
  required RuntimeTarget launchTarget,
  AcpSshLaunch? sshLaunch,
}) {
  if (!usesSshTransport(launchTarget.kind)) return null;
  final launch = sshLaunch;
  if (launch == null) {
    throw StateError(
      'Remote ACP launch requires an SSH launch (profile + channel opener)',
    );
  }
  return sshAcpTransportStarter(
    profile: launch.profile,
    openChannel: launch.openChannel,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/cubits/session/acp/acp_transport_wiring_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_transport_wiring.dart client/test/cubits/session/acp/acp_transport_wiring_test.dart
git commit -m "feat(acp): add SSH transport starter and remote command builder"
```

---

### Task 5: Remote personal staging selection

**Files:**
- Modify: `client/lib/services/chat/launch/connect/acp_launch_environment.dart`
- Test: `client/test/services/chat/launch/acp_launch_environment_test.dart`

**Interfaces:**
- Consumes: `prepareSimpleConnect` result record `({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})`.
- Produces:
  - `typedef AcpPreparedSimpleConnect = ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})`.
  - `typedef AcpPersonalLaunch = ({Map<String, String> env, String executable, String sessionToolDir})`.
  - `AcpPersonalLaunch selectAcpRemoteLaunch({required AcpPreparedSimpleConnect prepared, required String localExecutable, required String localSessionToolDir})`.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/chat/launch/acp_launch_environment_test.dart`:

```dart
  test('selectAcpRemoteLaunch keeps the work-plane env and remote paths', () {
    final prepared = (
      shellLaunch: ShellLaunchSpec(
        plan: LaunchPlan(
          env: const {
            'PATH': '/remote/bin',
            'CLAUDE_CONFIG_DIR': '/remote/cfg/s1',
          },
          resume: false,
          taskId: 's1',
          cliTeamName: '',
          memberConfigDir: '/remote/cfg/s1',
          resolvedRoots: const [],
        ),
        launchContext: const CliLaunchContext(
          team: TeamProfile(id: 't', name: 't'),
          member: TeamMemberConfig(id: 's1', name: 's1'),
        ),
      ),
      warnings: const <String>[],
      remoteCliPath: '/remote/bin/opencode',
    );

    final selected = selectAcpRemoteLaunch(
      prepared: prepared,
      localExecutable: '/usr/bin/opencode',
      localSessionToolDir: '/home/u/.local/share/tp/s1/opencode',
    );

    expect(selected.executable, '/remote/bin/opencode');
    expect(selected.sessionToolDir, '/remote/cfg/s1');
    expect(selected.env['PATH'], '/remote/bin');
    expect(selected.env['CLAUDE_CONFIG_DIR'], '/remote/cfg/s1');
  });

  test('selectAcpRemoteLaunch falls back to local values when remote is empty',
      () {
    final prepared = (
      shellLaunch: ShellLaunchSpec(
        plan: LaunchPlan(
          env: const {'PATH': '/remote/bin'},
          resume: false,
          taskId: 's1',
          cliTeamName: '',
          memberConfigDir: '',
          resolvedRoots: const [],
        ),
        launchContext: const CliLaunchContext(
          team: TeamProfile(id: 't', name: 't'),
          member: TeamMemberConfig(id: 's1', name: 's1'),
        ),
      ),
      warnings: const <String>[],
      remoteCliPath: '',
    );

    final selected = selectAcpRemoteLaunch(
      prepared: prepared,
      localExecutable: '/usr/bin/opencode',
      localSessionToolDir: '/home/u/.local/share/tp/s1/opencode',
    );

    expect(selected.executable, '/usr/bin/opencode');
    expect(selected.sessionToolDir, '/home/u/.local/share/tp/s1/opencode');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_launch_environment_test.dart --plain-name "selectAcpRemoteLaunch"`
Expected: FAIL — `selectAcpRemoteLaunch` undefined.

- [ ] **Step 3: Implement**

Append to `client/lib/services/chat/launch/connect/acp_launch_environment.dart`:

```dart
/// Result shape of `prepareSimpleConnect` / `prepareTeamConnect`.
typedef AcpPreparedSimpleConnect = ({
  ShellLaunchSpec shellLaunch,
  List<String> warnings,
  String remoteCliPath,
});

/// Values the personal ACP cubit starts with.
typedef AcpPersonalLaunch = ({
  Map<String, String> env,
  String executable,
  String sessionToolDir,
});

/// Selects remote personal ACP launch values from the staging result.
///
/// The staged work-plane env already carries the remote `PATH` and config
/// dirs, so it is used verbatim — never overwritten with the local `PATH`.
/// Empty remote values fall back to the local CLI path / home-plane session
/// tool dir so a partially populated stager cannot start a session with an
/// empty executable.
AcpPersonalLaunch selectAcpRemoteLaunch({
  required AcpPreparedSimpleConnect prepared,
  required String localExecutable,
  required String localSessionToolDir,
}) {
  final remoteCli = prepared.remoteCliPath.trim();
  final memberConfigDir = prepared.shellLaunch.plan.memberConfigDir.trim();
  return (
    env: Map<String, String>.of(prepared.shellLaunch.plan.env),
    executable: remoteCli.isEmpty ? localExecutable : remoteCli,
    sessionToolDir: memberConfigDir.isEmpty
        ? localSessionToolDir
        : memberConfigDir,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_launch_environment_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/connect/acp_launch_environment.dart client/test/services/chat/launch/acp_launch_environment_test.dart
git commit -m "feat(acp): select remote personal launch values from staging"
```

---

### Task 6: Route personal ACP sessions to the SSH starter

**Files:**
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Modify: `client/lib/services/chat/launch/session_launch_service.dart:58-112`
- Test: `client/test/services/chat/launch/acp_runtime_attach_test.dart` (extend the `_Host` double with a `lifecycle` + `stateSnapshot`, then add a mixed-gate regression test and a personal-remote test — see note). **Also required:** `client/test/services/chat/launch/acp_member_idle_test.dart` and `client/test/services/chat/launch/session_launch_acp_attach_test.dart` each need the same `_Host` completion (`lifecycle` + `stateSnapshot`), because `attachAcpRuntime` now always reads the launch target; without it their existing tests throw `NoSuchMethodError`.

**Interfaces:**
- Consumes: `AcpSshLaunch` / `AcpSshLaunchFactory` / `acpStarterForTarget` (Task 4); `selectAcpRemoteLaunch` / `AcpPreparedSimpleConnect` (Task 5); `SshMemberSession.open` / `openExec` (Task 2); `DartSsh2AcpChannel` (Task 1); `usesSshTransport` (`lib/models/runtime_target.dart`).
- Produces: `AcpRuntimeAttach` gains constructor fields `AcpSshLaunchFactory? sshLaunchFactory` and `AcpRemoteStagingBuilder? prepareRemoteStaging`; `SessionLaunchService` gains matching test seams `prepareAcpSshLaunch`, `prepareAcpRemoteStaging`.

**Test coverage:** `attachAcpRuntime` reads the launch target through `SessionLaunchService._launchWorkTarget`, which delegates to `_h.lifecycle`. The existing `_Host` test double returns `null` for that getter (`noSuchMethod`), so Step 5 gives it a tiny `_FakeLifecycle` returning a configurable `RuntimeTarget`. That is required regardless (otherwise the existing `attachAcpRuntime` personal test would start throwing `NoSuchMethodError` once the target is read), and it also makes the personal-remote branch unit-testable: with the injected `prepareAcpRemoteStaging` / `prepareAcpSshLaunch` seams, the test asserts the remote staging values reach `cubit.start`. Opening a real channel against a real sshd remains a `@Tags(['integration'])` follow-up.

- [ ] **Step 1: Add the remote staging seam + `AcpRemoteStagingBuilder`**

Append to `client/lib/services/chat/launch/connect/acp_launch_environment.dart`:

```dart
/// Test seam: skips the production remote staging (`prepareSimpleConnect`).
typedef AcpRemoteStagingBuilder = Future<AcpPreparedSimpleConnect> Function({
  required AppSession session,
  required Workspace workspace,
  required RuntimeTarget launchTarget,
});
```

Add the `AppSession` / `Workspace` / `RuntimeTarget` imports if missing (they are already imported in this file).

- [ ] **Step 2: Wire `AcpRuntimeAttach`**

In `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`:

Add imports:
```dart
import '../../../acp/acp_ssh_transport.dart';
import '../../session/chat_tab.dart'; // already imported
import '../../../../cubits/session/acp/acp_transport_wiring.dart';
import '../../../ssh/ssh_member_session.dart';
```
(`runtime_target.dart` is already imported; `usesSshTransport` comes from it.)

Add constructor fields (next to `preparePersonalContribution`):
```dart
    this.prepareRemoteStaging,
    this.sshLaunchFactory,
```
and the members:
```dart
  /// Test seam: skip the production remote staging.
  final AcpRemoteStagingBuilder? prepareRemoteStaging;

  /// Test seam: skip opening a real member SSH session.
  final AcpSshLaunchFactory? sshLaunchFactory;
```

Replace `attachAcpRuntime` (currently lines 88-125) with:

```dart
  /// Terminal-less personal ACP: attach a cubit and spawn `session.cli`
  /// locally, or on the remote host when the launch target uses SSH.
  Future<bool> attachAcpRuntime(
    SessionConnectJob job,
    AppSession session,
  ) async {
    final tab = _host.tabStore.getOpenTabBySessionId(session.sessionId);
    if (tab == null) return false;
    final existing = tab.acpRuntime;
    if (existing != null) {
      _host.updateTabRunning(tab.info.id);
      return true;
    }
    final cli = session.cli;
    if (cli == null) {
      throw StateError('ACP session requires session.cli');
    }
    final workspace = job.workspace ?? workspaceById(session.workspaceId);
    final launchTarget = launchWorkTarget(session);
    final remote = usesSshTransport(launchTarget.kind);
    final workingDirectory = _personalWorkingDirectory(session, job.workspace);

    late final String executable;
    late final String sessionToolDir;
    late final Map<String, String> baseEnv;
    if (remote) {
      if (workspace == null) {
        throw StateError('Simple session requires workspace');
      }
      final build = prepareRemoteStaging ?? _productionRemoteStaging;
      final prepared = await build(
        session: session,
        workspace: workspace,
        launchTarget: launchTarget,
      );
      final selected = selectAcpRemoteLaunch(
        prepared: prepared,
        localExecutable: _host.shellFactory.executableFor(cli),
        localSessionToolDir: _sessionToolDir(session, cli),
      );
      executable = selected.executable;
      sessionToolDir = selected.sessionToolDir;
      baseEnv = selected.env;
    } else {
      executable = _host.shellFactory.executableFor(cli);
      sessionToolDir = _sessionToolDir(session, cli);
      baseEnv = await _personalLaunchEnv(session, job, workspace);
    }

    final sshLaunch = remote
        ? (sshLaunchFactory ?? _productionSshLaunch)(
            session: session,
            launchTarget: launchTarget,
          )
        : null;

    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: true,
      memberId: null,
      launchTarget: launchTarget,
      sshLaunch: sshLaunch,
      processWorkingDirectory: workingDirectory,
    );
    tab.acpRuntime = cubit;
    _host.updateTabRunning(tab.info.id);
    await cubit.start(
      executable: executable,
      sessionToolDir: sessionToolDir,
      workingDirectory: workingDirectory,
      baseEnv: baseEnv,
      permissionPolicy: session.acpPermission,
    );
    if (_host.isClosed) return true;
    _host.finishSessionConnect(session.sessionId);
    _host.updateTabRunning(tab.info.id);
    return true;
  }

  /// Production remote staging: the same orchestration the PTY path uses, so
  /// the remote workspace is provisioned and `remoteCliPath` /
  /// `plan.memberConfigDir` / `plan.env` are the remote values.
  Future<AcpPreparedSimpleConnect> _productionRemoteStaging({
    required AppSession session,
    required Workspace workspace,
    required RuntimeTarget launchTarget,
  }) {
    return _host.sessionConnect.prepareSimpleConnect(
      session: session,
      workspace: workspace,
      launchTarget: launchTarget,
    );
  }

  /// Production SSH launch: opens (and stores on the tab) one member SSH
  /// session, then hands out exec channels over it. Stored under
  /// `session.sessionId` so [ChatTab.disposeBus] tears it down.
  AcpSshLaunch _productionSshLaunch({
    required AppSession session,
    required RuntimeTarget launchTarget,
  }) {
    final factory = _host.shellFactory.sshClientFactory;
    final profile = _host.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) {
      throw StateError(
        'ACP remote session requires an SSH profile and client factory',
      );
    }
    return (
      profile: profile,
      openChannel: (command) async {
        final tab = _host.tabStore.getOpenTabBySessionId(session.sessionId);
        if (tab == null) {
          throw StateError(
            'ACP remote session tab missing session=${session.sessionId}',
          );
        }
        final memberSession =
            tab.memberSshSessions[session.sessionId] ??
            await SshMemberSession.open(factory, profile);
        tab.memberSshSessions[session.sessionId] = memberSession;
        return DartSsh2AcpChannel(await memberSession.openExec(command));
      },
    );
  }
```

- [ ] **Step 3: Thread the target through `_cubit`**

Replace the `_cubit` signature and runtime construction (currently lines 278-309) with:

```dart
  AcpChatRuntimeCubit _cubit({
    required AppSession session,
    required CliTool cli,
    required bool personal,
    required String? memberId,
    required RuntimeTarget launchTarget,
    required String processWorkingDirectory,
    AcpSshLaunch? sshLaunch,
  }) {
    final remote = usesSshTransport(launchTarget.kind);
    final logger = AcpFrameLogger();
    final runtime =
        runtimeFactory?.call(logger: logger, tool: cli) ??
        AcpSessionRuntime(
          spawner: productionAcpSpawner(
            registry: _host.cliRegistry,
            tool: cli,
            workingDirectory: processWorkingDirectory,
            logger: logger,
            transportStarter: acpStarterForTarget(
              launchTarget: launchTarget,
              sshLaunch: sshLaunch,
            ),
          ),
          logger: logger,
          launchPlanFor: acpLaunchPlanResolver(
            _host.cliRegistry,
            // A local boot-time adapter path is meaningless on a remote host;
            // the remote PATH resolves the bare adapter name instead.
            discoveredAdapterPath: remote ? null : _host.discoveredAcpAdapterPath,
          ),
        );
    return AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: session.sessionId,
      tool: cli,
      seatMemberId: personal ? AcpChatRuntimeCubit.acpMemberId : memberId!,
      attention: _host.agentAttentionCubit,
      transcript: _transcript(session, memberId: memberId, personal: personal),
    )..ensureStrings(_host.acpChatStrings?.call(cli) ?? defaultAcpChatStrings);
  }
```

Update the member call site (`attachMemberAcpRuntime`, around line 211) to pass the new params — mixed remote stays on the PTY path, so no SSH launch:

```dart
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: false,
      memberId: member.id,
      launchTarget: launchTarget,
      sshLaunch: null,
      processWorkingDirectory: staged.workingDirectory,
    );
```

- [ ] **Step 4: Add the `SessionLaunchService` seams**

In `client/lib/services/chat/launch/session_launch_service.dart`:

Add constructor params after `acpMemberLifecycleGate` (line 67):
```dart
    this.prepareAcpRemoteStaging,
    this.prepareAcpSshLaunch,
```
and fields after `acpMemberLifecycleGate` (line 100):
```dart
  /// Test seam: skip the production remote ACP staging.
  final AcpRemoteStagingBuilder? prepareAcpRemoteStaging;

  /// Test seam: skip opening a real member SSH session for remote ACP.
  final AcpSshLaunchFactory? prepareAcpSshLaunch;
```

Pass them into the `AcpRuntimeAttach` construction (line 102-112):
```dart
    prepareRemoteStaging: prepareAcpRemoteStaging,
    sshLaunchFactory: prepareAcpSshLaunch,
```

Add imports for `AcpRemoteStagingBuilder` (from `connect/acp_launch_environment.dart`) and `AcpSshLaunchFactory` (from `cubits/session/acp/acp_transport_wiring.dart`).

- [ ] **Step 5: Extend the test harness and add the regression tests**

In `client/test/services/chat/launch/acp_runtime_attach_test.dart`:

**(a) Add these imports** (the four are new; the rest already exist):

```dart
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/chat/session/session_lifecycle_service.dart';
```

**(b) Make the harness target/seam-aware.** Change `_Harness` to:

```dart
class _Harness {
  _Harness({
    this.extra = const {
      'teammate-bus': {'type': 'http', 'url': 'http://127.0.0.1:9/mcp'},
    },
    this.gate,
    RuntimeTarget? launchTarget,
    this.remoteStaging,
    this.sshLaunchFactory,
  }) : launchTarget = launchTarget ?? RuntimeTarget.local() {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    materializer = _RecordingMaterializer(tabStore: tabStore);
    service = SessionLaunchService(
      _Host(tabStore, materializer, this.launchTarget),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) => runtime,
      prepareAcpContribution: (session, workspace) async => const {},
      prepareAcpTeamConnect:
          ({
            required session,
            required team,
            required member,
            required workspace,
            required launchTarget,
            required workingDirectory,
            extraMcpServers,
          }) async {
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'ACP_TEAM_STAGING': 'mixed-lead'},
                  resume: false,
                  taskId: member.id,
                  cliTeamName: team.name,
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: team,
                  member: member,
                  workingDirectory: workingDirectory,
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      acpMemberExtraMcp: ({required session, required member}) => extra,
      acpMemberLifecycleGate: gate,
      prepareAcpRemoteStaging: remoteStaging,
      prepareAcpSshLaunch: sshLaunchFactory,
    );
  }

  final Map<String, Map<String, Object?>> extra;
  final AcpMemberLifecycleGate? gate;
  final RuntimeTarget launchTarget;
  final AcpRemoteStagingBuilder? remoteStaging;
  final AcpSshLaunchFactory? sshLaunchFactory;
  // ...the remaining fields (`runtime`, `materializer`, `tabStore`, `tab`,
  // `service`) are unchanged.
}
```

**(c) Add a fake lifecycle and wire it into `_Host`.** `_Host` currently gets `lifecycle` as `null` through `noSuchMethod`, which would make `_launchWorkTarget` throw once `attachAcpRuntime` reads the target:

```dart
class _FakeLifecycle implements SessionLifecycleService {
  _FakeLifecycle(this._target);

  final RuntimeTarget _target;

  @override
  RuntimeTarget launchWorkTarget(
    WorkspaceLaunchContext ctx, {
    String? memberId,
  }) => _target;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

and in `_Host`:

```dart
class _Host implements SessionLaunchHost {
  _Host(this.tabStore, this.memberMaterializer, this._launchTarget);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  final RuntimeTarget _launchTarget;

  @override
  SessionLifecycleService get lifecycle => _FakeLifecycle(_launchTarget);

  // ...the other overrides are unchanged.
}
```

**(d) Record the launch values** on `_RecordingAcpRuntime` so the remote test can assert them — add three fields and set them in `start`:

```dart
  String? executable;
  String? sessionToolDir;
  Map<String, String> baseEnv = const {};
```
```dart
    started = true;
    this.executable = executable;
    this.sessionToolDir = sessionToolDir;
    this.baseEnv = baseEnv;
    this.mcpServers = mcpServers;
    this.permissionPolicy = permissionPolicy;
```

**(e) Append the two tests inside `main()`:**

```dart
  test(
    'attachAcpRuntime routes a remote (ssh) personal session to remote staging values',
    () async {
      final harness = _Harness(
        launchTarget: RuntimeTarget.ssh('p1', label: 'host'),
        remoteStaging:
            ({
              required session,
              required workspace,
              required launchTarget,
            }) async => (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {
                    'PATH': '/remote/bin',
                    'CLAUDE_CONFIG_DIR': '/remote/cfg/s1',
                  },
                  resume: false,
                  taskId: 's1',
                  cliTeamName: '',
                  memberConfigDir: '/remote/cfg/s1',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: const TeamProfile(id: 't', name: 't'),
                  member: const TeamMemberConfig(id: 's1', name: 's1'),
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '/remote/bin/claude',
            ),
        sshLaunchFactory:
            ({required session, required launchTarget}) => (
              profile: const SshProfile(
                id: 'p1',
                name: 'host',
                host: 'host',
                username: 'u',
                authType: SshAuthType.password,
              ),
              // The injected `acpRuntimeFactory` replaces the production
              // spawner, so this opener is never invoked.
              openChannel: (_) async => throw UnimplementedError(),
            ),
      );
      final session = _personalSession();

      final handled = await harness.service.attachAcpRuntime(
        _personalJob(session),
        session,
      );

      expect(handled, isTrue);
      expect(harness.runtime.started, isTrue);
      expect(harness.runtime.executable, '/remote/bin/claude');
      expect(harness.runtime.sessionToolDir, '/remote/cfg/s1');
      expect(harness.runtime.baseEnv['PATH'], '/remote/bin');
      expect(harness.runtime.baseEnv['CLAUDE_CONFIG_DIR'], '/remote/cfg/s1');
    },
  );

  test('attachMemberAcpRuntime keeps a remote (ssh) member on the terminal',
      () async {
    final harness = _Harness();
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      sessionTeam: 'team-1',
      members: [
        SessionMemberBinding(
          rosterMemberId: 'lead',
          taskId: 'task-lead',
          cli: CliTool.claude,
          acp: true,
        ),
      ],
      memberTargets: const {'lead': 'ssh:p1'},
      createdAt: 1,
    );
    final team = _mixedTeam();
    final member = _lead();

    final handled = await harness.service.attachMemberAcpRuntime(
      _job(session, team, member),
      session,
      (team: team, member: member, cli: CliTool.claude),
    );

    expect(handled, isFalse);
    expect(harness.tab.memberAcpRuntimes, isEmpty);
    expect(harness.runtime.started, isFalse);
  });
```

(The member test intercepts its target via the injected `prepareAcpTeamConnect`, so `_memberLaunchTarget` reads `session.memberTargets['lead'] == 'ssh:p1'` without touching `_h.lifecycle`. The personal test reaches the target through `_FakeLifecycle`, which is also what keeps the pre-existing `attachAcpRuntime` personal test green.)

- [ ] **Step 6: Run the affected tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/services/chat/launch/acp_runtime_attach_test.dart test/cubits/session/acp/acp_launch_wiring_test.dart test/cubits/session/acp/acp_transport_wiring_test.dart test/services/chat/launch/acp_launch_environment_test.dart test/services/acp/acp_ssh_transport_test.dart`
Expected: analyze clean; all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/chat/launch/connect/acp_runtime_attach.dart \
        client/lib/services/chat/launch/connect/acp_launch_environment.dart \
        client/lib/services/chat/launch/session_launch_service.dart \
        client/test/services/chat/launch/acp_runtime_attach_test.dart
git commit -m "feat(acp): run personal ACP sessions on remote SSH targets"
```

---

### Task 7: Docs + full verification

**Files:**
- Modify: `docs/ARCHITECTURE.md` (ACP / remote transport note)

- [ ] **Step 1: Document the seam**

In `docs/ARCHITECTURE.md`, add a short subsection under the chat / ACP area (match the surrounding heading level and style):

```markdown
### ACP remote transport

`services/acp/` keeps a byte-pipe seam (`AcpTransport`). Two implementations
exist: `AcpProcessTransport` (local `dart:io` process) and `AcpSshTransport`
(non-PTY SSH exec channel, `dartssh2`). `productionAcpSpawner`
(`cubits/session/acp/acp_launch_wiring.dart`) picks one through the
`AcpTransportStarter` seam; `acpStarterForTarget` chooses the SSH starter when
the launch target uses SSH transport. Remote executable / env / config-dir
values come from the PTY staging path
(`SessionConnectOrchestrator.prepareSimpleConnect`), selected by
`selectAcpRemoteLaunch`.

Phase 1 covers **personal (simple) ACP sessions on desktop SSH targets**.
Mixed-team remote seats (`member_acp_stamp.dart` `_memberAcpGates`), remote MCP
reachability, remote adapter install, and SSH reconnect for an in-flight ACP
seat are not implemented.
```

- [ ] **Step 2: Full analyze + suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze clean; full suite PASS.

- [ ] **Step 3: Manual verification (desktop, real sshd)**

1. Create an SSH workspace whose folder target is `ssh:<profile>`.
2. Create a **personal** OpenCode (or Cursor) session there with the "Personal sessions use ACP chat" preference on.
3. Confirm the session opens as chat-only (no terminal toggle) and the agent responds.
4. On the remote host, `ps aux | grep -E 'opencode|cursor'` shows the agent running **there** (not on the desktop).
5. Confirm `~/.local/share/com.hhoa.teampilot/.../sessions/<id>/runtime/` on the remote host receives staging, and the desktop did **not** spawn a local agent.
6. Point the workspace at a host where the CLI is missing: the session should end with the existing ACP launch error (version/adapter), not a local spawn.

Record the exact commands/output for each check before claiming the feature works.

- [ ] **Step 4: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "docs: document the ACP remote (SSH) transport seam"
```

---

## Self-Review

- **Spec coverage:** Remote transport → Task 1. Non-PTY exec channel → Task 2. Spawner routing seam → Tasks 3-4. Remote env/path/executable staging → Task 5. Personal attach wiring + mixed gate unchanged + seams → Task 6. Docs/verification → Task 7.
- **Placeholder scan:** no TBD/"handle edge cases"/"similar to Task N"; every code step carries full code.
- **Type consistency:** `AcpTransportStarter`/`AcpStartedTransport` (Task 3) are reused verbatim in Task 4 and Task 6; `AcpSshChannel`/`AcpSshTransport` (Task 1) are reused in Task 4; `AcpPreparedSimpleConnect`/`selectAcpRemoteLaunch` (Task 5) are reused in Task 6; `AcpSshLaunch`/`AcpSshLaunchFactory`/`acpStarterForTarget` (Task 4) are reused in Task 6.
- **Known gap:** the personal-remote attach is unit-tested (Task 6) via the injected staging/SSH-launch seams plus the `_FakeLifecycle` harness completion; the only uncovered part is opening a **real** channel against a **real** sshd. Add a `@Tags(['integration'])` test when such a harness exists.

## Follow-Up Plans (not detailed here)

1. **Mixed-team remote ACP seats** — relax `_memberAcpGates` for SSH, cover `attachMemberAcpRuntime` remote staging, and handle the bus-MCP requirement.
2. **Remote MCP reachability** — forward `RemoteBusBinding`/`agentStatus`/tunnel ports through the ACP path so remote agents can reach TeamBus and Session SSH MCP.
3. **Remote adapter install/locate** — a remote adapter path override + `RemoteCliReadinessService`/`installAdapter` integration so Claude/Codex do not depend on the remote `PATH`.
4. **SSH reconnect for ACP seats** — subscribe to `SshProfileConnectionCoordinator.sessionReconnectSignals` and re-spawn/reattach the remote ACP transport.
5. **Android/Termux ACP** — relax the `isAndroid` gate and handle Termux `$PREFIX` paths once desktop SSH is stable.
