# SSH Task-Plane Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long-running remote command (CLI/adapter install, provisioning) that exceeds its own budget must fail that command only — never a home-liveness transition, never a full-page "retry" replacement of the shell.

**Architecture:** Four changes, layered:
1. A new non-durable close reason (`commandTimeout`) that the transport-close policy ignores.
2. Worker-side command cancellation: the storage exec session is closed on timeout and the caller receives `command_timeout`; only stdin-backed launches still retire the storage plane, and even then with the non-durable reason.
3. The home-connectivity supervisor gains a `degraded` derivation: with the I/O gate up and the connection monitor healthy, a retired storage lease is "storage warming", not "home down".
4. Install/provision work moves to a short-lived member-plane channel (`RemoteInstallTask`) with its own budget; the readiness panel converts failures to inline UI, and `StartupGate` keeps the shell for transient mid-session drops (banner owns that surface).

**Tech Stack:** Dart 3 / Flutter, `dartssh2` (vendored), SSH worker isolates, `flutter_bloc`, `equatable`, `flutter_test`.

## Global Constraints

- **Never** run `flutter test` directly. Always `cd client && dart run tool/run_tests.dart <paths>`; run in the background only for the full suite.
- Inner loop is `cd client && flutter analyze`; run only the test files that cover the change.
- No `print`; diagnostics go through `appLogger` (already imported where referenced).
- Do not change legacy (`_connector != null`) test-only semantics beyond the reason value passed to `_evictLegacyProfile`.
- Keep `SshTransportPlane` unchanged; the task plane is an SSH *member* transport, not a new close plane.
- User-facing strings must come from l10n; this plan adds no new strings (it reuses `RemoteCliFailed` rendering).
- Commit after every task. Do not push.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `client/lib/services/ssh/ssh_transport_close.dart` | Add non-durable `commandTimeout` reason + expected-local classification |
| `client/lib/services/ssh/ssh_transport_close_policy.dart` | Short-circuit `commandTimeout` to `ignore` before plane rules |
| `client/lib/services/ssh/worker/ssh_worker_storage_backend.dart` | `cancelRun()` on the backend contract + dart exec-session tracking |
| `client/lib/services/ssh/worker/ssh_worker_storage_core.dart` | Map `runStorage` timeout to `command_timeout` and cancel only that run |
| `client/lib/services/ssh/worker/ssh_worker_storage_client.dart` | Reply grace so the worker's `command_timeout` wins the race |
| `client/lib/services/ssh/ssh_client_factory.dart` | Translate `command_timeout`; retire as `commandTimeout` not `transportError` |
| `client/lib/services/ssh/ssh_client_factory_legacy_storage.dart` | Same classification for the legacy connector path |
| `client/lib/services/ssh/ssh_client_factory_storage.dart` | Pool `onTimeout` retirement reason |
| `client/lib/services/ssh/ssh_home_connectivity_derive.dart` | **New** pure derivation table (extracted from the supervisor) |
| `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart` | Delegate `_derive` to the pure helper; degraded phase |
| `client/lib/services/cli/remote_install_task.dart` | **New** member-plane task channel + `SshCommandRunner` adapter |
| `client/lib/services/remote/remote_cli_readiness.dart` | Installs use `RemoteInstallTask` instead of the storage plane |
| `client/lib/services/cli/cli_installer_service.dart` | Default SSH install path opens/closes one task channel |
| `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart` | Catch install failures into `RemoteCliFailed` (no unhandled async error) |
| `client/lib/cubits/home_connection_cubit.dart` | `hasConnectedOnce` for gate hysteresis |
| `client/lib/pages/startup_gate.dart` | Keep the shell on transient post-connect drops |
| `client/test/services/ssh/...`, `client/test/services/remote/...`, `client/test/services/cli/...`, `client/test/pages/startup_gate_test.dart` | Tests |

---

### Task 1: Non-durable `commandTimeout` close reason

**Files:**
- Modify: `client/lib/services/ssh/ssh_transport_close.dart:1-78`
- Modify: `client/lib/services/ssh/ssh_transport_close_policy.dart:43-60`
- Test: `client/test/services/ssh/ssh_transport_close_policy_test.dart`

**Interfaces:**
- Produces: `SshTransportCloseReason.commandTimeout` — consumed by Tasks 2, 3.
- Produces: `SshTransportClosePolicy.evaluate` returns `SshTransportCloseDecision.ignore` for that reason on both planes.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/ssh/ssh_transport_close_policy_test.dart` inside `main()`:

```dart
  test('a command timeout never moves durable home state', () {
    for (final plane in SshTransportPlane.values) {
      final decision = SshTransportClosePolicy.evaluate(
        SshTransportClosed(
          reason: SshTransportCloseReason.commandTimeout,
          plane: plane,
        ),
      );
      expect(decision, SshTransportCloseDecision.ignore);
      expect(decision.affectsDurableHome, isFalse);
      expect(decision.emitDisconnectNotification, isFalse);
      expect(decision.scheduleStorageReconnect, isFalse);
    }
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_transport_close_policy_test.dart`
Expected: FAIL — `commandTimeout` is not defined.

- [ ] **Step 3: Add the reason and classification**

In `ssh_transport_close.dart`, extend the enum (after `transportError`):

```dart
  transportError,

  /// One command exceeded its own budget. The transport may still be healthy,
  /// so this must never move durable home state (see policy).
  commandTimeout,
```

Add the case in `isExpectedLocalSshTransportClose` (before `transportError`):

```dart
    case SshTransportCloseReason.commandTimeout:
      return true;
```

Returning `true` also makes `isSshConnectionFailure` treat a flattened
`commandTimeout` close as "not a connection failure", which is correct.

In `ssh_transport_close_policy.dart`, make the reason authoritative before
either plane branch:

```dart
  static SshTransportCloseDecision evaluate(SshTransportClosed closed) {
    if (closed.reason == SshTransportCloseReason.commandTimeout) {
      return SshTransportCloseDecision.ignore;
    }
    if (closed.plane == SshTransportPlane.member) {
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_transport_close_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/ssh/ssh_transport_close.dart lib/services/ssh/ssh_transport_close_policy.dart test/services/ssh/ssh_transport_close_policy_test.dart`
Expected: no issues (the exhaustive switch forces you to handle the new value).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/ssh_transport_close.dart client/lib/services/ssh/ssh_transport_close_policy.dart client/test/services/ssh/ssh_transport_close_policy_test.dart
git commit -m "feat(ssh): classify command timeouts as non-durable transport closes"
```

---

### Task 2: Worker-exec cancellation instead of whole-plane invalidation

**Files:**
- Modify: `client/lib/services/ssh/worker/ssh_worker_storage_backend.dart:10-35,86-144`
- Modify: `client/lib/services/ssh/worker/ssh_worker_storage_core.dart:43-50`
- Test: `client/test/services/ssh/worker/ssh_worker_storage_core_test.dart`

**Interfaces:**
- Produces: `SshWorkerStorageBackend.cancelRun()` (void, closes in-flight non-stdin exec sessions).
- Produces: worker reply code `command_timeout`; no `transportClosed` event for a non-stdin timeout.
- Consumes: `SshTransportCloseReason.commandTimeout` from Task 1 (stdin path only).

- [ ] **Step 1: Write the failing test**

In `client/test/services/ssh/worker/ssh_worker_storage_core_test.dart`, add a test and extend `_FakeBackend`:

```dart
  test('a timed-out storage exec cancels only that command', () async {
    final events = <SshWorkerEvent>[];
    final backend = _FakeBackend()..hangRun = true;
    final core = SshWorkerStorageCore(
      backend: backend,
      sendEvent: events.add,
    );
    await core.handle(_request(SshWorkerOperation.connectStorage));

    final reply = await core.handle(
      SshWorkerRequest(
        requestId: 'run-timeout',
        operation: SshWorkerOperation.runStorage,
        args: const {'command': 'sleep 600', 'stderr': true, 'timeoutMs': 10},
      ),
    );

    expect(reply.error?.code, 'command_timeout');
    expect(backend.cancelRunCalls, 1);
    expect(
      events.where((event) => event.kind == SshWorkerEventKind.transportClose),
      isEmpty,
    );

    backend.hangRun = false;
    final next = await core.handle(
      SshWorkerRequest(
        requestId: 'run-ok',
        operation: SshWorkerOperation.runStorage,
        args: const {'command': 'true', 'stderr': true},
      ),
    );
    expect(next.kind, SshWorkerReplyKind.success);
  });
```

Replace `_FakeBackend.run` (currently `throw UnimplementedError()`) and add fields:

```dart
  var hangRun = false;
  var cancelRunCalls = 0;
  final _pendingRuns = <Completer<SshWorkerRunResult>>[];

  @override
  Future<SshWorkerRunResult> run(
    String command, {
    required bool stderr,
    Uint8List? stdin,
  }) {
    if (!hangRun) {
      return Future.value(
        SshWorkerRunResult(
          stdout: Uint8List(0),
          stderr: Uint8List(0),
          exitCode: 0,
        ),
      );
    }
    final pending = Completer<SshWorkerRunResult>();
    _pendingRuns.add(pending);
    return pending.future;
  }

  @override
  void cancelRun() {
    cancelRunCalls++;
    for (final pending in _pendingRuns) {
      if (!pending.isCompleted) {
        pending.completeError(
          const SshWorkerTransportException('cancelled', code: 'cancelled'),
        );
      }
    }
    _pendingRuns.clear();
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_storage_core_test.dart`
Expected: FAIL — `_FakeBackend` is missing `cancelRun`, and the reply code is `transport_timeout`.

- [ ] **Step 3: Add `cancelRun` and exec tracking**

In `ssh_worker_storage_backend.dart`, extend the interface:

```dart
abstract interface class SshWorkerStorageBackend {
  Future<void> connect(SshWorkerRequest request);
  Future<SshWorkerRunResult> run(
    String command, {
    required bool stderr,
    Uint8List? stdin,
  });

  /// Closes in-flight exec sessions without touching the shared transport.
  /// A stdin-backed run cannot be listed here (see `run`).
  void cancelRun();
```

In `SshWorkerDartStorageBackend`, add state and tracking:

```dart
  final Set<SSHSession> _activeRuns = {};
```

In `run`, wrap only the non-stdin branch:

```dart
    final session = await _client!.execute(command);
    _activeRuns.add(session);
    final stdoutBytes = BytesBuilder(copy: false);
    final stderrBytes = BytesBuilder(copy: false);
    var total = 0;
    Future<void> collect(
      Stream<Uint8List> stream,
      BytesBuilder target,
      bool capture,
    ) async {
      await for (final bytes in stream) {
        if (!capture) continue;
        total += bytes.length;
        if (total > sshWorkerMaxStorageExecOutput) {
          session.close();
          throw const SshWorkerTransportException(
            'Exec output limit exceeded',
            code: 'output_limit',
          );
        }
        target.add(bytes);
      }
    }

    try {
      await Future.wait([
        collect(session.stdout, stdoutBytes, true),
        collect(session.stderr, stderrBytes, stderr),
        session.done,
      ], eagerError: true);
      return SshWorkerRunResult(
        stdout: stdoutBytes.takeBytes(),
        stderr: stderrBytes.takeBytes(),
        exitCode: session.exitCode,
        signalName: session.exitSignal?.signalName,
        maxOutputBytes: sshWorkerMaxStorageExecOutput,
      );
    } finally {
      _activeRuns.remove(session);
      session.close();
    }
```

Add `cancelRun`, then make `close()` cancel in-flight runs:

```dart
  @override
  void cancelRun() {
    for (final session in _activeRuns.toList(growable: false)) {
      unawaited(_closeCancelledRun(session));
    }
  }

  Future<void> _closeCancelledRun(SSHSession session) async {
    try {
      // `SSHSession.close()` is synchronous and discards the channel's close
      // future, so await the channel directly: a failure is observed here and
      // swallowed rather than escaping as an unhandled zone error.
      await session.channel.close();
    } on Object {
      // Keep the session tracked; a later cancel/close retries the teardown.
      return;
    }
    _activeRuns.remove(session);
  }

  @override
  void close() {
    cancelRun();
    _epoch++;
    _client = null;
    final sftp = _sftp;
    _sftp = null;
    if (sftp != null) {
      unawaited(sftp.close().catchError((Object _) {}));
    }
    // The SSH client is owned by SshWorkerSharedClient and may still serve
    // member/forward planes; only the storage-local SFTP view is closed here.
  }
```

- [ ] **Step 4: Map the timeout in the worker core**

Replace the `on TimeoutException` block in `ssh_worker_storage_core.dart`:

```dart
    } on TimeoutException {
      if (request.operation == SshWorkerOperation.runStorage &&
          request.payload == null) {
        backend.cancelRun();
        return _error(request, 'command_timeout');
      }
      invalidate(
        request.operation == SshWorkerOperation.runStorage
            ? SshTransportCloseReason.commandTimeout
            : SshTransportCloseReason.transportError,
      );
      return _error(
        request,
        request.operation == SshWorkerOperation.runStorage
            ? 'command_timeout'
            : 'transport_timeout',
      );
```

Why: a plain exec can be killed without touching the transport. A stdin-backed
launch (`runWithResult`) cannot enumerate its session, so the plane is retired —
but as a command-scoped reason that Task 1 ignores.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_storage_core_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/worker/ssh_worker_storage_backend.dart client/lib/services/ssh/worker/ssh_worker_storage_core.dart client/test/services/ssh/worker/ssh_worker_storage_core_test.dart
git commit -m "feat(ssh-worker): cancel a timed-out exec instead of retiring the storage plane"
```

---

### Task 3: Factory and pool translate `command_timeout` without a home-down signal

**Files:**
- Modify: `client/lib/services/ssh/worker/ssh_worker_storage_client.dart:357-409`
- Modify: `client/lib/services/ssh/ssh_client_factory.dart:301-383`
- Modify: `client/lib/services/ssh/ssh_client_factory_legacy_storage.dart:6-27`
- Modify: `client/lib/services/ssh/ssh_client_factory_storage.dart:186-201`
- Test: `client/test/services/ssh/worker/ssh_worker_storage_client_timeout_test.dart` (new)

**Interfaces:**
- Consumes: reply code `command_timeout` (Task 2) and reason `commandTimeout` (Task 1).
- Produces: `runOnStorage`/`runOnStorageWithStdin` still throw `TimeoutException` on budget exhaustion; `SshWorkerStoragePool` lives are retired with `SshTransportCloseReason.commandTimeout`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/ssh/worker/ssh_worker_storage_client_timeout_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_client.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('the client waits past its own budget for the worker verdict', () async {
    var onTimeoutCalls = 0;
    final transport = SshWorkerLeaseStorageTransport.forTesting(
      (request) {
        // The worker answers just after the client's nominal budget.
        return Future.delayed(
          const Duration(milliseconds: 30),
          () => SshWorkerReply.failure(
            request.requestId,
            const SshWorkerErrorRecord(
              code: 'command_timeout',
              message: 'timed out',
            ),
          ),
        );
      },
      requestTimeout: const Duration(milliseconds: 10),
      onTimeout: () => onTimeoutCalls++,
    );
    final client = SshWorkerStorageClient(
      transport,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      client.run('sleep 1', timeout: const Duration(milliseconds: 10)),
      throwsA(
        isA<SshWorkerTransportException>().having(
          (error) => error.code,
          'code',
          'command_timeout',
        ),
      ),
    );
    expect(onTimeoutCalls, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_storage_client_timeout_test.dart`
Expected: FAIL — the client's `.timeout(effectiveTimeout)` fires first and yields `transport_timeout`.

- [ ] **Step 3: Add the reply grace**

In `ssh_worker_storage_client.dart`, add a constant near the top-level
cleanup timeout:

```dart
/// The worker runs its own budget (`timeoutMs`) and answers `command_timeout`
/// or `transport_timeout`. The client must give that reply a round-trip window
/// instead of racing it with an identical deadline.
const _sshWorkerReplyGrace = Duration(seconds: 5);
```

Change the send in `_request`:

```dart
    final reply;
    try {
      reply = await _send(request).timeout(effectiveTimeout + _sshWorkerReplyGrace);
```

- [ ] **Step 4: Classify at the factory boundary**

In `ssh_client_factory.dart`, `runOnStorage` catch block becomes:

```dart
    } on SshWorkerTransportException catch (error) {
      if (error.code == 'command_timeout') {
        throw TimeoutException('storage exec', timeout);
      }
      if (error.code != 'transport_timeout') rethrow;
      // The worker stopped answering: rebuild the lease, but as a command-scoped
      // fault so home state, monitor and gate stay up.
      _workerStoragePool.disconnectStorage(
        profile.id,
        reason: SshTransportCloseReason.commandTimeout,
      );
      throw TimeoutException('storage exec', timeout);
    }
```

Apply the same shape to `runOnStorageWithStdin` (message `'storage exec stdin'`).

Legacy `_runOnLegacyStorage` in `ssh_client_factory_legacy_storage.dart`:

```dart
    } on TimeoutException {
      _evictLegacyProfile(
        profile.id,
        closePooled: true,
        reason: SshTransportCloseReason.commandTimeout,
      );
      rethrow;
    }
```

And the legacy stdin branch in `ssh_client_factory.dart` (`runOnStorageWithStdin`)
uses `reason: SshTransportCloseReason.commandTimeout` in its
`_evictLegacyProfile` call.

Pool `onTimeout` in `ssh_client_factory_storage.dart`:

```dart
        onTimeout: () {
          if (identical(_connections[profile.id], connection)) {
            _retireConnection(
              profile.id,
              connection,
              reason: SshTransportCloseReason.commandTimeout,
            );
          }
        },
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_storage_client_timeout_test.dart test/services/ssh/worker/ssh_worker_storage_core_test.dart test/services/ssh/ssh_transport_close_policy_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/worker/ssh_worker_storage_client.dart client/lib/services/ssh/ssh_client_factory.dart client/lib/services/ssh/ssh_client_factory_legacy_storage.dart client/lib/services/ssh/ssh_client_factory_storage.dart client/test/services/ssh/worker/ssh_worker_storage_client_timeout_test.dart
git commit -m "fix(ssh): give the worker verdict precedence over the client deadline"
```

---

### Task 4: `degraded` home phase (storage warming, link healthy)

**Files:**
- Create: `client/lib/services/ssh/ssh_home_connectivity_derive.dart`
- Modify: `client/lib/services/ssh/ssh_home_connectivity_supervisor.dart:253-291`
- Test: `client/test/services/ssh/ssh_home_connectivity_derive_test.dart` (new)

**Interfaces:**
- Produces: `deriveSshHomeConnectivityState({required SshHomeConnectivityState previous, required bool storageLive, required RemoteConnectionStatus monitorStatus, required SshConnectionGateState gateState, bool planeRebinding = false}) → SshHomeConnectivityState`.
- Consumes: `SshPhase.degraded` (already mapped to `connected` by `AppShell` and `SshConnectionCubit`).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/ssh/ssh_home_connectivity_derive_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/remote_connection_monitor.dart';
import 'package:teampilot/services/ssh/ssh_connection_gate.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_derive.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_state.dart';

void main() {
  SshHomeConnectivityState derive({
    SshPhase phase = SshPhase.unreachable,
    bool storageLive = false,
    RemoteConnectionStatus monitor = RemoteConnectionStatus.connected,
    SshConnectionGateState gate = SshConnectionGateState.up,
    bool planeRebinding = false,
  }) => deriveSshHomeConnectivityState(
    previous: SshHomeConnectivityState(profileId: 'p', phase: phase),
    storageLive: storageLive,
    monitorStatus: monitor,
    gateState: gate,
    planeRebinding: planeRebinding,
  );

  test('a retired lease with a healthy gate and link is degraded, not down', () {
    final state = derive();
    expect(state.phase, SshPhase.degraded);
    expect(state.storageLive, isFalse);
    expect(state.isDown, isFalse);
  });

  test('a live lease beats every other signal', () {
    final state = derive(
      phase: SshPhase.failed,
      storageLive: true,
      monitor: RemoteConnectionStatus.reconnecting,
      gate: SshConnectionGateState.down,
    );
    expect(state.phase, SshPhase.up);
    expect(state.storageLive, isTrue);
  });

  test('an in-flight dial stays connecting', () {
    expect(derive(phase: SshPhase.connecting).phase, SshPhase.connecting);
  });

  test('a reconnecting monitor wins over a healthy gate', () {
    expect(
      derive(monitor: RemoteConnectionStatus.reconnecting).phase,
      SshPhase.reconnecting,
    );
  });

  test('a sticky failure is preserved', () {
    expect(derive(phase: SshPhase.failed).phase, SshPhase.failed);
  });

  test('a suspended gate stays suspended', () {
    expect(
      derive(gate: SshConnectionGateState.suspended).phase,
      SshPhase.suspended,
    );
  });

  test('a closed gate is unreachable even with a healthy monitor', () {
    expect(
      derive(gate: SshConnectionGateState.down).phase,
      SshPhase.unreachable,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_derive_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the pure derivation**

Create `client/lib/services/ssh/ssh_home_connectivity_derive.dart`:

```dart
import '../remote/remote_connection_monitor.dart';
import 'ssh_connection_gate.dart';
import 'ssh_home_connectivity_state.dart';

/// Pure phase table for one SSH home. Extracted so each priority rule is
/// testable without a factory, worker or coordinator.
SshHomeConnectivityState deriveSshHomeConnectivityState({
  required SshHomeConnectivityState previous,
  required bool storageLive,
  required RemoteConnectionStatus monitorStatus,
  required SshConnectionGateState gateState,
  bool planeRebinding = false,
}) {
  final id = previous.profileId;
  if (storageLive) {
    return SshHomeConnectivityState.up(
      id,
    ).copyWith(planeRebinding: planeRebinding);
  }
  if (previous.phase == SshPhase.connecting) {
    return previous.copyWith(storageLive: false);
  }
  if (monitorStatus == RemoteConnectionStatus.reconnecting) {
    return previous.copyWith(phase: SshPhase.reconnecting, storageLive: false);
  }
  if (previous.phase == SshPhase.failed) {
    return previous.copyWith(storageLive: false);
  }
  if (gateState == SshConnectionGateState.suspended) {
    return previous.copyWith(phase: SshPhase.suspended, storageLive: false);
  }
  // Gate open + link healthy: only the storage lease retired (command timeout,
  // probe failure). Keep the shell; the next storage read reopens the lease.
  // Deliberately excludes `idle`: a boot that never opened the gate must still
  // surface `unreachable`, not silently claim a healthy degraded home.
  if (gateState == SshConnectionGateState.up &&
      (monitorStatus == RemoteConnectionStatus.connected ||
          monitorStatus == RemoteConnectionStatus.degraded)) {
    return previous.copyWith(
      phase: SshPhase.degraded,
      storageLive: false,
      clearFailure: true,
      clearErrorDetail: true,
    );
  }
  return previous.copyWith(phase: SshPhase.unreachable, storageLive: false);
}
```

- [ ] **Step 4: Delegate from the supervisor**

Replace `_derive` (lines 253-291) with:

```dart
  SshHomeConnectivityState _derive(String id) {
    return deriveSshHomeConnectivityState(
      previous: stateFor(id),
      storageLive: _factory.hasLiveStorageClient(id),
      monitorStatus: _coordinator.monitorFor(id).state.status,
      gateState: _gate.stateOf(id),
      planeRebinding: _planeRebinding && id == _activeHomeId,
    );
  }
```

Add the import:

```dart
import 'ssh_home_connectivity_derive.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_home_connectivity_derive_test.dart test/services/ssh/ssh_home_connectivity_supervisor_test.dart`
Expected: PASS. If an existing supervisor test expected `unreachable` for a
storage-only retire with a healthy gate/monitor, update that expectation to
`degraded` (the new intended behavior) rather than changing the helper.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/ssh_home_connectivity_derive.dart client/lib/services/ssh/ssh_home_connectivity_supervisor.dart client/test/services/ssh/ssh_home_connectivity_derive_test.dart client/test/services/ssh/ssh_home_connectivity_supervisor_test.dart
git commit -m "feat(ssh): derive a degraded home phase when only storage is warming"
```

---

### Task 5: `RemoteInstallTask` on the member plane

**Files:**
- Create: `client/lib/services/cli/remote_install_task.dart`
- Modify: `client/lib/services/remote/remote_cli_readiness.dart:137-154,302-324,376-393`
- Test: `client/test/services/cli/remote_install_task_test.dart` (new)
- Test: `client/test/services/remote/remote_cli_readiness_adapter_test.dart` (extend)

**Interfaces:**
- Consumes: `SshClientFactory.openMemberTransport(SshProfile, {Duration timeout})` (existing) and `SshWorkerMemberTransport.run` (existing, no worker timeout).
- Produces: `RemoteInstallTask.open(SshClientFactory, SshProfile, {Duration connectTimeout, Duration commandTimeout})`, `RemoteInstallTask.runner` (`SshCommandRunner`), `RemoteInstallTask.close()`.
- Produces: `installRunnerForRemoteTask(RemoteInstallTask)` → `SshCliInstallRunner` (consumed by Task 6).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/remote_install_task_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/remote_install_task.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

const _profile = SshProfile(
  id: 'p1',
  label: 'box',
  host: 'example.com',
  port: 22,
  username: 'dev',
);

void main() {
  test('runner decodes member exec output', () async {
    final transport = _FakeMemberTransport(
      (command) async => SshWorkerRunResult(
        stdout: Uint8List.fromList('done\n'.codeUnits),
        stderr: Uint8List(0),
        exitCode: 0,
      ),
    );
    final task = await RemoteInstallTask.open(_FakeFactory(transport), _profile);
    addTearDown(task.close);

    final result = await task.runner('echo done');

    expect(result.exitCode, 0);
    expect(result.stdout, 'done\n');
    expect(result.stderr, isEmpty);
  });

  test('a command budget closes only the task channel', () async {
    final transport = _FakeMemberTransport(
      (command) => Completer<SshWorkerRunResult>().future,
    );
    final task = await RemoteInstallTask.open(
      _FakeFactory(transport),
      _profile,
      commandTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(task.close);

    await expectLater(
      task.runner('sleep 600'),
      throwsA(isA<TimeoutException>()),
    );
    expect(transport.closed, 1);
  });
}

final class _FakeFactory implements SshClientFactory {
  _FakeFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  _FakeMemberTransport(this._onRun);
  final Future<SshWorkerRunResult> Function(String command) _onRun;
  var closed = 0;

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {}

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) =>
      _onRun(command);

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}
```

Note: the first test opens a throwaway task; simplify it to a single task in
the implementation step if you prefer, but keep both assertions: decoded
output and no transport leak.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/remote_install_task_test.dart`
Expected: FAIL — `remote_install_task.dart` does not exist.

- [ ] **Step 3: Implement the task channel**

Create `client/lib/services/cli/remote_install_task.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import '../../models/ssh_profile.dart';
import '../ssh/ssh_client_factory.dart';
import '../ssh/worker/ssh_worker_member_session.dart';
import '../ssh/worker/ssh_worker_storage_types.dart';
import 'installer_types.dart';
import 'registry/capabilities/cli_executable_capability.dart';

/// One short-lived member-plane exec channel for long install/provision work.
///
/// The member plane has no worker-side command timeout and does not invalidate
/// the storage plane; closing this lease never moves home connectivity state.
final class RemoteInstallTask {
  RemoteInstallTask._(this._transport, {required this.commandTimeout});

  /// Long enough for npm/Node bootstrap/downloads, short enough to end a wedge.
  static const defaultCommandTimeout = Duration(minutes: 10);

  /// Closing must never outlive the install outcome on a wedged worker.
  static const _closeTimeout = Duration(seconds: 10);

  /// Reply grace over the worker's own open timeout: a wedged isolate that
  /// never answers must not leave the install job non-terminal.
  static const _openGrace = Duration(seconds: 5);

  static Future<RemoteInstallTask> open(
    SshClientFactory factory,
    SshProfile profile, {
    Duration connectTimeout = const Duration(seconds: 15),
    Duration commandTimeout = defaultCommandTimeout,
  }) async {
    final transport = await factory.openMemberTransport(
      profile,
      timeout: connectTimeout,
    );
    try {
      await transport
          .open(profile, timeout: connectTimeout)
          .timeout(connectTimeout + _openGrace);
    } on Object {
      try {
        await transport.close().timeout(_closeTimeout);
      } on Object {
        // The channel may already be gone; never mask the connect failure.
      }
      rethrow;
    }
    return RemoteInstallTask._(transport, commandTimeout: commandTimeout);
  }

  final SshWorkerMemberTransport _transport;
  final Duration commandTimeout;
  Future<void>? _closeFuture;

  SshCommandRunner get runner => (command) async {
    final SshWorkerRunResult result;
    try {
      result = await _transport.run(
        command,
        stderr: true,
      ).timeout(commandTimeout);
    } on TimeoutException {
      await close();
      rethrow;
    }
    return SshCommandResult(
      exitCode: result.exitCode ?? 1,
      stdout: utf8.decode(result.stdout, allowMalformed: true),
      stderr: utf8.decode(result.stderr, allowMalformed: true),
    );
  };

  Future<void> close() => _closeFuture ??= _close();

  /// Closing must never outlive the install outcome on a wedged worker.
  static const _closeTimeout = Duration(seconds: 10);

  Future<void> _close() async {
    try {
      await _transport.close().timeout(_closeTimeout);
    } on Object {
      // The channel may already be gone; a close failure must never mask the
      // install outcome or the timeout that triggered it.
    }
  }
}

/// Adapts a [RemoteInstallTask] to `CliInstallerService`'s SSH runner.
SshCliInstallRunner installRunnerForRemoteTask(RemoteInstallTask task) =>
    (SshProfile profile, CliInstallerCommand command) async {
      final result = await task.runner(command.commandLine);
      return CliInstallerCommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    };
```

- [ ] **Step 4: Route readiness installs through the task plane**

In `remote_cli_readiness.dart`, add the import:

```dart
import '../cli/remote_install_task.dart';
```

Add the helper after `_runnerFor`:

```dart
  Future<T> _withInstallRunner<T>(
    SshProfile profile,
    Future<T> Function(SshCommandRunner run) body,
  ) async {
    final override = _remoteRunnerFor;
    if (override != null) {
      return body(override(profile, includeStderr: true));
    }
    final task = await RemoteInstallTask.open(
      sshClientFactory,
      profile,
      commandTimeout: RemoteInstallTask.defaultCommandTimeout,
    );
    try {
      return await body(task.runner);
    } finally {
      await task.close();
    }
  }
```

In `_installCli`, replace the runner acquisition and the `_installer.ensure` call:

```dart
      final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
          .trim();
      final path = await _withInstallRunner(profile, (run) {
        return _installer.ensure(
          cli: cli,
          run: run,
          optIn: true,
          supportsInstaller: true,
          install:
              _installActionBuilder?.call(cli, profile, run) ??
              buildRemotePreflightCliInstall(
                registry: registry,
                profile: profile,
                cli: cli,
              ),
          manualPathOverride: storedPath,
          onProgress: onProgress,
        );
      });
```

In `_installAdapter`, replace the runner acquisition and locate/install block:

```dart
      final path = await _withInstallRunner(profile, (run) async {
        final existing = await _locateAdapterWithRun(
          target: target,
          cli: cli,
          run: run,
        );
        return existing ??
            await (_adapterInstallActionBuilder?.call(
                      installer,
                      profile,
                      run,
                    ) ??
                    buildRemotePreflightAdapterInstall(
                      installer: installer,
                      profile: profile,
                    ))(run: run, onProgress: onProgress ?? (_) {});
      });
```

Leave `probe`/`locate` on `_runnerFor` (the storage plane) — they are short.
Retries stay idempotent: the stored `manualPathOverride` and the
locate-before-install check inside `_installAdapter` are unchanged, so a failed
install retried from the panel never reinstalls a healthy binary.

- [ ] **Step 5: Prove readiness installs use the task channel**

Existing tests pass a `remoteRunnerFor` override, so they stay green. Add one
test in `remote_cli_readiness_adapter_test.dart` that removes the override and
asserts the member task is opened and closed:

```dart
  test('install(adapter) uses the member task when no runner is injected', () async {
    overrides = {};
    final transport = _FakeMemberTransport();
    final service = RemoteCliReadinessService(
      registry: CliToolRegistry.builtIn(),
      sshClientFactory: _TaskFactory(transport),
      profileById: (_) => const SshProfile(
        id: 'host-a',
        name: 'host',
        host: 'host',
        username: 'u',
      ),
      cliPathOverride: (_, __) async => null,
      setCliPathOverride: (_, __, ___) async {},
      acpAdapterPathOverride: (_, __) async => null,
      setAcpAdapterPathOverride: (_, __, ___) async {},
    );

    final result = await service.install(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(result, isA<RemoteCliReady>());
    expect(transport.opened, 1);
    expect(transport.closed, 1);
    expect(transport.commands, isNotEmpty);
  });
```

Add the fakes at the bottom of that file:

```dart
final class _TaskFactory implements SshClientFactory {
  _TaskFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  var opened = 0;
  var closed = 0;
  final commands = <String>[];

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => opened++;

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    commands.add(command);
    return SshWorkerRunResult(
      stdout: Uint8List.fromList(
        '/home/u/.local/bin/claude-agent-acp\n'.codeUnits,
      ),
      stderr: Uint8List(0),
      exitCode: 0,
    );
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}
```

Add these imports to that file:

```dart
import 'dart:typed_data';

import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';
```

`_locateAdapterWithRun` finds the adapter on the first command, so the fake
transport never needs to run an installer; the assertion is the channel
lifecycle, not the install script.

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/remote_install_task_test.dart test/services/remote/remote_cli_readiness_adapter_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/remote_install_task.dart client/lib/services/remote/remote_cli_readiness.dart client/test/services/cli/remote_install_task_test.dart client/test/services/remote/remote_cli_readiness_adapter_test.dart
git commit -m "feat(remote-cli): run installs on a member-plane task channel"
```

---

### Task 6: `CliInstallerService` opens the task channel by default

**Files:**
- Modify: `client/lib/services/cli/cli_installer_service.dart:25-56,106-135`
- Test: `client/test/services/cli/cli_installer_service_task_plane_test.dart` (new)

**Interfaces:**
- Consumes: `RemoteInstallTask.open`, `RemoteInstallTask.close`, `installRunnerForRemoteTask` (Task 5).
- Produces: `CliInstallerService.install` / `installAdapter` in `CliInstallMode.ssh` use one member-plane task per call when no runner override is injected; the task is always closed.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/cli/cli_installer_service_task_plane_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

const _profile = SshProfile(
  id: 'p1',
  label: 'box',
  host: 'example.com',
  port: 22,
  username: 'dev',
);

void main() {
  test('SSH adapter install opens and closes exactly one task channel', () async {
    final transport = _FakeMemberTransport();
    final factory = _FakeFactory(transport);
    final service = CliInstallerService(sshClientFactory: factory);

    final result = await service.installAdapter(
      installer: _FakeAdapter(),
      mode: CliInstallMode.ssh,
      sshProfile: _profile,
    );

    expect(result.success, isTrue);
    expect(result.executablePath, '/usr/local/bin/test-adapter');
    expect(transport.opened, 1);
    expect(transport.closed, 1);
    expect(transport.commands.single, contains('test-adapter'));
  });
}

final class _FakeAdapter implements AcpAdapterInstaller {
  @override
  String get adapterJobTarget => 'adapter:test';
  @override
  String get executableName => 'test-adapter';
  @override
  String get displayName => 'Test adapter';
  @override
  bool get supportsInstaller => true;
  @override
  Future<String?> resolveInstalledPath() async => null;
  @override
  Future<String?> latestVersion() async => null;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    final result = await context.host.runSsh(
      context.sshProfile!,
      CliInstallerCommand.unixShellScript(
        'echo /usr/local/bin/test-adapter',
      ),
    );
    return CliInstallResult(
      success: result.exitCode == 0,
      message: 'ok',
      executablePath: result.stdout.trim(),
    );
  }
}

final class _FakeFactory implements SshClientFactory {
  _FakeFactory(this.transport);
  final SshWorkerMemberTransport transport;

  @override
  Future<SshWorkerMemberTransport> openMemberTransport(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => transport;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _FakeMemberTransport implements SshWorkerMemberTransport {
  var opened = 0;
  var closed = 0;
  final commands = <String>[];

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async => opened++;

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async {
    commands.add(command);
    return SshWorkerRunResult(
      stdout: Uint8List.fromList('/usr/local/bin/test-adapter\n'.codeUnits),
      stderr: Uint8List(0),
      exitCode: 0,
    );
  }

  @override
  Future<SshWorkerExecChannel> startProcess(String command) =>
      throw UnimplementedError();

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async => closed++;
}
```

The fake adapter parses the resolved path from `runSsh`'s stdout, so the fake
transport must answer with the path line; `opened`/`closed` prove the task
channel lifecycle.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_installer_service_task_plane_test.dart`
Expected: FAIL — `openMemberTransport` receives no call because the service
still builds `_SshCommandRunner`.

- [ ] **Step 3: Open the task channel for the duration of the install**

Replace the constructor field initialization:

```dart
  }) : _localRunner = localRunner ?? _runLocal,
       _sshRunnerOverride = sshRunner,
       _sshClientFactory = sshClientFactory,
       _hostEnvironment =
```

Replace the `_sshRunner` field:

```dart
  final SshCliInstallRunner? _sshRunnerOverride;
  final SshClientFactory? _sshClientFactory;
  late SshCliInstallRunner _sshRunner =
      _sshRunnerOverride ?? _SshCommandRunner(_sshClientFactory).run;
```

Adjust `_runInstall` (keep the body and add task lifecycle):

```dart
    _onProgress = onProgress;
    _isCancelled = isCancelled;
    _onProcessStarted = onProcessStarted;
    final profile = sshProfile;
    RemoteInstallTask? task;
    try {
      if (mode == CliInstallMode.ssh &&
          profile != null &&
          _sshRunnerOverride == null &&
          _sshClientFactory != null) {
        task = await RemoteInstallTask.open(_sshClientFactory, profile);
        _sshRunner = installRunnerForRemoteTask(task);
      }
      return await install(
        CliInstallContext(
          mode: mode,
          host: _CliInstallerHost(this),
          hostEnvironment: _hostEnvironment,
          sshProfile: sshProfile,
          node: TeampilotNodeInstall.standard,
        ),
      );
    } finally {
      _onProgress = null;
      _isCancelled = null;
      _onProcessStarted = null;
      if (task != null) {
        _sshRunner = _SshCommandRunner(_sshClientFactory).run;
        await task.close();
      }
    }
```

Add the import:

```dart
import 'remote_install_task.dart';
```

Do not touch `buildRemotePreflightCliInstall` / `buildRemotePreflightAdapterInstall`: they construct the service with an injected `sshRunner`, so the override branch keeps them on the caller's preflight transport.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/cli_installer_service_task_plane_test.dart test/services/cli/remote_install_task_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_installer_service.dart client/test/services/cli/cli_installer_service_task_plane_test.dart
git commit -m "feat(cli): make SSH installs use the member-plane task by default"
```

---

### Task 7: Install failures become inline UI, not unhandled async errors

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart:156-237`
- Test: `client/test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart`

The test file already exists with a `_wrap` harness and `_FakeReadiness`; extend them.

**Interfaces:**
- Consumes: `RemoteCliReadinessService.install` returning `RemoteCliFailed` on failure (existing) and `InstallJobRegistry.enqueue` completing with an error (existing).
- Produces: `_install` never leaves an uncaught error; the row shows `RemoteCliFailed` (message + retry button).

- [ ] **Step 1: Write the failing test**

Add imports:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
```

Add the test inside `main()` (the Flutter test framework fails the test on the
pre-fix unhandled async error):

```dart
  testWidgets('a failed install renders inline', (tester) async {
    final progressCubit = ProgressActivityCubit(
      historyRecorder: _FakeRecorder(),
    );
    final installRegistry = InstallJobRegistry(progressCubit: progressCubit);
    addTearDown(() async {
      installRegistry.dispose();
      await progressCubit.close();
    });

    await tester.pumpWidget(
      _wrap(
        RemoteCliMachineReadinessPanel(
          fixedRequirements: const [
            RemoteCliRequirement(
              target: target,
              cli: CliTool.claude,
              hostLabel: 'Build host',
              kind: CliBinaryKind.adapter,
            ),
          ],
          selectableTargets: const [target],
          readiness: _FakeReadiness(failInstall: true),
        ),
        installRegistry: installRegistry,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('install failed'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });
```

Update `_wrap`:

```dart
Widget _wrap(Widget child, {InstallJobRegistry? installRegistry}) {
  final theme = buildDarkTheme();
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: installRegistry == null
            ? Scaffold(body: child)
            : Provider<InstallJobRegistry>.value(
                value: installRegistry,
                child: Scaffold(body: child),
              ),
      ),
    ),
  );
}
```

Update `_FakeReadiness`:

```dart
class _FakeReadiness extends RemoteCliReadinessService {
  _FakeReadiness({this.failInstall = false})
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  final bool failInstall;

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async => RemoteCliMissing(targetId: target.id, cli: cli);

  @override
  Future<RemoteCliReadiness> install({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async => failInstall
      ? RemoteCliFailed(
          targetId: target.id,
          cli: cli,
          message: 'install failed',
        )
      : RemoteCliMissing(targetId: target.id, cli: cli);
}

final class _FakeRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}
```

If `NotificationRecorder`'s import path differs, copy it from
`client/test/pages/onboarding/cli_step_test.dart` (the file already has this
fake).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart`
Expected: FAIL — the `StateError` from `_install` reaches the zone (and no
inline failure is rendered).

- [ ] **Step 3: Catch the job failure into readiness state**

In `_install`, wrap the enqueue/result block:

```dart
      await registry.enqueue(
        InstallJobSpec<RemoteCliReadiness>(
          key: key,
          title: 'Install $adapterLabel on $hostLabel',
          workspaceId: widget.workspace?.workspaceId,
          cancelPolicy: InstallCancelPolicy.cooperative,
          historyMessageFor: (readiness) => switch (readiness) {
            RemoteCliReady() => '$adapterLabel ready on $hostLabel',
            _ => null,
          },
          run: (ctx) async {
            final readiness = await widget.readiness.install(
              target: requirement.target,
              cli: requirement.cli,
              kind: requirement.kind,
              onProgress: (progress) {
                final phaseLabel = switch (progress.phase) {
                  CliInstallPhase.checkingNpm => 'Checking npm',
                  CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
                  CliInstallPhase.installingCli => 'Installing CLI',
                  CliInstallPhase.locatingExecutable => 'Locating executable',
                  CliInstallPhase.downloading => 'Downloading adapter',
                  CliInstallPhase.extracting => 'Extracting adapter',
                  CliInstallPhase.syncingRemoteWorkspace =>
                    'Syncing remote workspace',
                };
                final detail = progress.detail?.trim();
                if (detail != null && detail.isNotEmpty) {
                  ctx.reportPhase(phaseLabel, detail: detail);
                } else {
                  ctx.reportPhase(phaseLabel);
                }
              },
            );
            if (readiness is RemoteCliFailed) {
              throw StateError(readiness.message);
            }
            return readiness;
          },
        ),
      );
```

Keeping the `StateError` preserves job-history failure semantics. Add the
catch around the whole `try` body:

```dart
    } on Object catch (error) {
      final message = error is StateError ? error.message : '$error';
      appLogger.w(
        '[remote-cli] install failed '
        'target=${requirement.target.id} cli=${requirement.cli.value}: '
        '$message',
        error: error,
      );
      if (mounted) {
        setState(() {
          _readinessByKey[requirement.cacheKey] = RemoteCliFailed(
            targetId: requirement.target.id,
            cli: requirement.cli,
            message: message,
          );
        });
      }
    } finally {
```

Add the import for logging if the file does not already import it:

```dart
import '../../../utils/logging/logger.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart client/test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart
git commit -m "fix(ui): render remote install failures inline instead of throwing"
```

---

### Task 8: Keep the shell on transient post-connect drops

**Files:**
- Modify: `client/lib/cubits/home_connection_cubit.dart:7-60,82-119,173-241`
- Modify: `client/lib/pages/startup_gate.dart:37-68`
- Test: `client/test/pages/startup_gate_test.dart`

**Interfaces:**
- Produces: `HomeConnectionState.hasConnectedOnce` (bool) — set on `connectOnce` success, `markReconnected`, `markInitial(reachable)`; reset on `rebind` when the profile id changes.
- Produces: `StartupGate` keeps `child` for `reconnecting`/`unreachable` when `hasConnectedOnce && lastErrorKind == null`; otherwise it shows `RemoteConnectionsPage`.

- [ ] **Step 1: Write the failing tests**

Add two cases to `client/test/pages/startup_gate_test.dart` using the existing
`_gateHost` harness:

```dart
  testWidgets('a transient drop after a healthy session keeps the shell', (
    tester,
  ) async {
    final homeCubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.unknown),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
      host: 'example.com',
      port: 22,
    );
    addTearDown(homeCubit.close);
    homeCubit.markReconnected();
    homeCubit.markBackgroundAttempt(2);

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => true,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsOneWidget);
    expect(find.byType(RemoteConnectionsPage), findsNothing);
  });

  testWidgets('a permanent failure after a healthy session shows the page', (
    tester,
  ) async {
    final homeCubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.unknown),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
      host: 'example.com',
      port: 22,
    );
    addTearDown(homeCubit.close);
    homeCubit.markReconnected();
    homeCubit.markUnreachable(HomeErrorKind.hostIdentityChanged);

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => true,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.byType(RemoteConnectionsPage), findsOneWidget);
  });
```

The `connect` callback is never invoked here; keep it a valid
`HomeConnectResult` so the test compiles. `markReconnected()` sets both the
status and `hasConnectedOnce`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/startup_gate_test.dart`
Expected: FAIL — the first case still shows `RemoteConnectionsPage`.

- [ ] **Step 3: Add `hasConnectedOnce` to the cubit**

Add to `HomeConnectionState`:

```dart
  final bool hasConnectedOnce;

  const HomeConnectionState({
    this.status = HomeConnectionStatus.connecting,
    this.profileId,
    this.host,
    this.port,
    this.attempt = 0,
    this.lastErrorKind,
    this.hasConnectedOnce = false,
  });
```

Add it to `copyWith`:

```dart
  HomeConnectionState copyWith({
    HomeConnectionStatus? status,
    String? profileId,
    String? host,
    int? port,
    int? attempt,
    Object? lastErrorKind = _unset,
    bool? hasConnectedOnce,
  }) => HomeConnectionState(
    status: status ?? this.status,
    profileId: profileId ?? this.profileId,
    host: host ?? this.host,
    port: port ?? this.port,
    attempt: attempt ?? this.attempt,
    lastErrorKind: identical(lastErrorKind, _unset)
        ? this.lastErrorKind
        : lastErrorKind as HomeErrorKind?,
    hasConnectedOnce: hasConnectedOnce ?? this.hasConnectedOnce,
  );
```

Add it to `props` and set it on every "connected" transition:
`connectOnce` success, `markReconnected`, `markInitial` when reachable, and
`markPlaneReady`.

`rebind` must reset it when the identity changes:

```dart
    emit(
      HomeConnectionState(
        status: identityChanged
            ? HomeConnectionStatus.connecting
            : state.status,
        profileId: profileId,
        host: host,
        port: port,
        attempt: identityChanged ? 0 : state.attempt,
        lastErrorKind: identityChanged ? null : state.lastErrorKind,
        hasConnectedOnce: identityChanged ? false : state.hasConnectedOnce,
      ),
    );
```

- [ ] **Step 4: Let the gate keep the shell**

Replace the status switch block in `startup_gate.dart`:

```dart
    var keepShellDuringDrop = false;
    if (homeConn != null) {
      switch (homeConn.status) {
        case HomeConnectionStatus.connecting:
          return _HomeConnectingPage(state: homeConn);
        case HomeConnectionStatus.unreachable:
        case HomeConnectionStatus.reconnecting:
          // A successful session already rendered the shell; a transient drop
          // is owned by the banner + inline retries. Permanent failures
          // (host identity, auth) still need the full connection page.
          // `SshHomeDisconnectedBanner` reads `SshConnectionCubit`, which keeps
          // reporting reconnecting during the coordinator's retry loop.
          if (homeConn.hasConnectedOnce && homeConn.lastErrorKind == null) {
            keepShellDuringDrop = true;
          } else {
            return const RemoteConnectionsPage();
          }
        case HomeConnectionStatus.connected:
          break;
      }
    }

    final homeConnected = homeConn?.status == HomeConnectionStatus.connected;

    if (!homeConnected && !keepShellDuringDrop && mode.requiresSshProfileSetup) {
      return const RemoteConnectionsPage();
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/startup_gate_test.dart test/cubits/home_connection_cubit_test.dart`
Expected: PASS. Update any existing cubit test constructing `HomeConnectionState`
positionally if the new field shifts a positional argument (use named args).

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/home_connection_cubit.dart client/lib/pages/startup_gate.dart client/test/pages/startup_gate_test.dart client/test/cubits/home_connection_cubit_test.dart
git commit -m "feat(startup): keep the shell across transient home drops"
```

---

## Verification

- [ ] Analyze: `cd client && flutter analyze lib/services/ssh lib/services/cli lib/services/remote lib/cubits/home_connection_cubit.dart lib/pages/startup_gate.dart lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- [ ] Focused suites:

```bash
cd client && dart run tool/run_tests.dart \
  test/services/ssh \
  test/services/cli/remote_install_task_test.dart \
  test/services/cli/cli_installer_service_task_plane_test.dart \
  test/services/remote/remote_cli_readiness_adapter_test.dart \
  test/pages/startup_gate_test.dart
```

- [ ] Full suite before delivery (background): `cd client && dart run tool/run_tests.dart`
- [ ] Manual smoke (desktop, SSH workspace): start a CLI install that sleeps past its budget (set `provisionPhaseTimeout` low in a debug build or simulate with a slow network); confirm the editor/terminal stay visible, the readiness row shows the failure with a retry button, and no `RemoteConnectionsPage` appears. Then drop the SSH host (stop sshd) and confirm the full page appears as before after the retry loop gives up.

## Out of Scope

- Probes (`probe`/`locate`) stay on the storage plane; only installs/provisioning move.
- No new l10n strings; failures reuse the existing `RemoteCliFailed` row.
- The `RemoteConnectionMonitor` heartbeat remains the authority for real link loss.
