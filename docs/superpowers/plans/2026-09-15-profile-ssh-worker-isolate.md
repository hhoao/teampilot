# Profile-Scoped SSH Worker Isolate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Move each SSH profile's SSH protocol, SFTP, exec, and PTY ownership into one long-lived worker isolate while preserving TeamPilot's existing storage/member/reconnect behavior and improving UI responsiveness under SSH load.

**Architecture:** Add a profile-scoped worker manager and a primitive-only message protocol. The worker isolate owns all dartssh2 objects; the UI isolate owns a facade, Flutter/plugin interactions, reconnect policy, and terminal rendering. Migrate storage first, then member/PTY, with a direct-mode adapter for deterministic unit tests and a measured production cutover.

**Tech Stack:** Dart 3.8 isolates and SendPort/ReceivePort, TransferableTypedData, Flutter services, vendored dartssh2, existing SshClientFactory, SshProfileConnectionCoordinator, SFTP/PTY integration tests, and dart run tool/run_tests.dart.

## Global Constraints

- Never invoke flutter test directly; run tests through cd client && dart run tool/run_tests.dart ....
- Before claiming completion run cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart.
- Every Isolate.spawn/Isolate.run must provide a descriptive debugName.
- No SSHClient, SftpClient, SSHSession, repository, Flutter object, or callback crosses the isolate boundary.
- Keep SshProfileConnectionCoordinator as the authority for profile-level disconnect coalescing and reconnect decisions.
- Preserve SshTransportPlane.storage versus SshTransportPlane.member semantics.
- Keep credential and known-host repository access in the UI isolate behind request/reply challenges; never log private keys, passwords, or passphrases.
- Use injected connectors, worker launchers, and filesystem/network fakes in unit tests.
- Use @Tags(['integration']) for new real SSH/Docker/integration tests.
- Do not use Directory.current for workspace or app-data roots.
- User-visible errors remain l10n-backed; diagnostics use AppLogger, never print.
- Keep changed service files below the repository's ~600-line soft limit; split protocol, worker lifecycle, storage, and PTY responsibilities into separate files.

---

## File Map

Create the worker implementation under client/lib/services/ssh/worker/:

- ssh_worker_protocol.dart: primitive wire DTOs, operation names, error and chunk records.
- ssh_worker_entry.dart: top-level isolate entry point and worker bootstrap.
- ssh_profile_worker.dart: worker-side SSH client/session/SFTP ownership and command dispatcher.
- ssh_profile_worker_manager.dart: UI-side profile-to-worker lifecycle, references, idle shutdown, and generations.
- ssh_profile_worker_client.dart: UI-side proxy for one profile worker.
- ssh_worker_auth_bridge.dart: host-key and credential challenge bridge.
- ssh_worker_storage_client.dart: storage-plane facade with exec and chunked SFTP methods.
- ssh_worker_member_session.dart: member-plane and PTY channel facade.
- ssh_worker_output_batcher.dart: worker-side PTY output coalescing and bounded queue.

Create focused tests under client/test/services/ssh/worker/:

- protocol serialization and malformed-message tests;
- worker manager lifecycle and generation tests;
- auth bridge tests;
- storage/chunk/backpressure tests;
- member/PTy/output batching tests.

Existing files are migrated in place:

- client/lib/services/ssh/ssh_client_factory.dart
- client/lib/services/ssh/ssh_member_session.dart
- client/lib/services/terminal/ssh_pty_transport.dart
- client/lib/services/storage/remote_file_store.dart
- client/lib/services/ssh/ssh_profile_connection_coordinator.dart
- client/lib/services/terminal/terminal_transport_factory.dart
- client/lib/app/app_shell.dart
- all direct clientForStorage, createMemberClient, sftpFor, and SSHClient call sites found by rg.

The existing SSH unit and integration tests remain the regression suite. Tests that currently construct fake SSHClient instances should migrate to the new narrow worker/storage/member seams instead of preserving a production API that returns dartssh2 objects.

---

### Task 1: Add the primitive worker wire protocol

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_protocol.dart
- Create: client/test/services/ssh/worker/ssh_worker_protocol_test.dart

**Interfaces:**
- Consumes: SshProfile.toJson(), SshTransportPlane, SSHRunResult semantics, and Dart primitive/typed-data isolate messages.
- Produces: SshWorkerOperation, SshWorkerRequest, SshWorkerReply, SshWorkerEvent, SshWorkerErrorRecord, SshWorkerProfileSnapshot, and SshWorkerDialTarget for Tasks 2–6.

- [ ] **Step 1: Write failing protocol tests**

Add tests for these exact behaviors:

~~~
test('request round-trips primitive fields and operation', () {
  const request = SshWorkerRequest(
    requestId: 'r1',
    operation: SshWorkerOperation.runStorage,
    args: {'command': 'printf ok', 'stderr': false},
  );

  final decoded = SshWorkerRequest.fromWire(request.toWire());

  expect(decoded.requestId, 'r1');
  expect(decoded.operation, SshWorkerOperation.runStorage);
  expect(decoded.args['command'], 'printf ok');
  expect(decoded.args['stderr'], false);
});

test('binary chunk carries stream sequencing and completion', () {
  final chunk = SshWorkerEvent.outputChunk(
    streamId: 'pty-1',
    sequence: 3,
    bytes: Uint8List.fromList([1, 2, 3]),
    isFinal: false,
  );

  final decoded = SshWorkerEvent.fromWire(chunk.toWire());

  expect(decoded.streamId, 'pty-1');
  expect(decoded.sequence, 3);
  expect(decoded.bytes, [1, 2, 3]);
  expect(decoded.isFinal, isFalse);
});

test('malformed operation and missing request id fail closed', () {
  expect(
    () => SshWorkerRequest.fromWire({'type': 'request', 'operation': 'bad'}),
    throwsFormatException,
  );
});
~~~

Run:

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_protocol_test.dart
~~~

Expected: FAIL because the protocol types do not exist.

- [ ] **Step 2: Implement the protocol types**

Define a closed operation enum containing at least:

~~~
enum SshWorkerOperation {
  connectStorage,
  runStorage,
  openSftpRead,
  writeSftpChunk,
  closeSftpStream,
  openMember,
  runMember,
  openPty,
  writePty,
  resizePty,
  closeChannel,
  cancelRequest,
  shutdown,
}
~~~

SshWorkerRequest.toWire() and fromWire() must use a Map<String, Object?> with a version field, request id, operation name, and primitive args. SshWorkerReply must distinguish success, failure, cancellation, and stream completion. SshWorkerEvent must distinguish state changes, auth challenges, output chunks, transfer progress, and transport close. Binary data must be represented as Uint8List/TransferableTypedData at the transport seam, never as a dartssh2 object.

Validate required strings, non-negative sequence numbers, operation names, and maximum declared chunk sizes in fromWire(). Convert malformed messages to FormatException with no secret payload included.

- [ ] **Step 3: Run the protocol tests**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_protocol_test.dart
~~~

Expected: PASS.

- [ ] **Step 4: Commit**

~~~
git add client/lib/services/ssh/worker/ssh_worker_protocol.dart client/test/services/ssh/worker/ssh_worker_protocol_test.dart
git commit -m "feat(ssh): add worker isolate wire protocol"
~~~

### Task 2: Implement worker lifecycle and a direct-mode test adapter

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_entry.dart
- Create: client/lib/services/ssh/worker/ssh_profile_worker.dart
- Create: client/lib/services/ssh/worker/ssh_profile_worker_client.dart
- Create: client/lib/services/ssh/worker/ssh_profile_worker_manager.dart
- Create: client/test/services/ssh/worker/ssh_profile_worker_manager_test.dart

**Interfaces:**
- Consumes: Task 1 protocol types.
- Produces: SshProfileWorkerManager.acquire(SshProfile profile), SshProfileWorkerClient.send(SshWorkerRequest), SshProfileWorkerClient.events, SshProfileWorkerClient.close(), and SshWorkerLauncher.

- [ ] **Step 1: Write failing lifecycle tests**

Cover these exact cases with an in-memory worker launcher:

~~~
test('same profile reuses one worker and reference counts leases', () async {
  final launcher = RecordingWorkerLauncher();
  final manager = SshProfileWorkerManager(launcher: launcher);
  const profile = testProfile;

  final first = await manager.acquire(profile);
  final second = await manager.acquire(profile);

  expect(identical(first.workerIdentity, second.workerIdentity), isTrue);
  expect(launcher.spawnCount, 1);
  await first.release();
  expect(launcher.shutdownCount, 0);
  await second.release();
  await manager.flushIdleShutdowns();
  expect(launcher.shutdownCount, 1);
});

test('old worker events cannot complete a new generation', () async {
  final launcher = RecordingWorkerLauncher();
  final manager = SshProfileWorkerManager(launcher: launcher);
  final first = await manager.acquire(testProfile);
  await manager.disconnectProfile(testProfile.id);
  final second = await manager.acquire(testProfile);

  launcher.emitFromGeneration(first.generation, staleReply);

  expect(second.pendingRequestIds, isNot(contains(staleReply.requestId)));
});

test('worker entry is spawned with an explicit debug name', () async {
  final launcher = RecordingWorkerLauncher();
  final manager = SshProfileWorkerManager(launcher: launcher);
  await (await manager.acquire(testProfile)).release();

  expect(launcher.debugNames.single, 'ssh-profile-worker:p1');
});
~~~

Run the focused test file and expect failure because the manager and launcher do not exist.

- [ ] **Step 2: Implement the worker actor and manager**

Define the isolate bootstrap as a top-level entry point:

~~~
void sshProfileWorkerMain(SshWorkerBootstrap bootstrap) {
  final worker = SshProfileWorker(
    bootstrap: bootstrap,
    send: bootstrap.uiPort.send,
  );
  worker.start();
}
~~~

SshWorkerLauncher.spawn must call Isolate.spawn(sshProfileWorkerMain, bootstrap, debugName: 'ssh-profile-worker:<profileId>'). The worker must listen for primitive wire messages, serialize replies, and close its ReceivePort on shutdown. The manager must keep profile.id -> generation/lease state, coalesce concurrent acquires, reject operations after shutdown begins, and use a bounded idle timer rather than leaking an isolate.

Add DirectSshWorkerLauncher for unit tests. It invokes the same SshProfileWorker with paired ports in the current isolate; it must not expose a production bypass or change production defaults.

- [ ] **Step 3: Run lifecycle tests and static analysis**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_profile_worker_manager_test.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Expected: focused tests PASS and analysis reports no new issues.

- [ ] **Step 4: Commit**

~~~
git add client/lib/services/ssh/worker/ssh_worker_entry.dart client/lib/services/ssh/worker/ssh_profile_worker.dart client/lib/services/ssh/worker/ssh_profile_worker_client.dart client/lib/services/ssh/worker/ssh_profile_worker_manager.dart client/test/services/ssh/worker/ssh_profile_worker_manager_test.dart
git commit -m "feat(ssh): add profile worker lifecycle"
~~~

### Task 3: Add UI-side auth and connection challenges

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_auth_bridge.dart
- Create: client/test/services/ssh/worker/ssh_worker_auth_bridge_test.dart
- Modify: client/lib/services/ssh/ssh_client_factory.dart
- Modify: client/lib/services/ssh/worker/ssh_profile_worker.dart

**Interfaces:**
- Consumes: Task 1 challenge events and Task 2 worker client.
- Produces: SshWorkerAuthBridge, SshWorkerAuthReply, and worker-side dartssh2 callbacks for password, private key, passphrase, host-key verification, and dial target resolution.

- [ ] **Step 1: Write failing auth bridge tests**

Test that the bridge calls existing injected dependencies and never sends secrets to logs:

~~~
test('host-key challenge delegates to trust policy and returns decision', () async {
  final prompts = <HostKeyPromptInfo>[];
  final bridge = SshWorkerAuthBridge(
    credentialStore: InMemorySshCredentialStore(),
    knownHostRepository: InMemorySshKnownHostRepository(),
    onHostKeyPrompt: (info) async {
      prompts.add(info);
      return true;
    },
  );

  final accepted = await bridge.verifyHostKey(
    profile: testProfile,
    keyType: 'ssh-ed25519',
    fingerprint: Uint8List.fromList([1, 2, 3]),
  );

  expect(accepted, isTrue);
  expect(prompts.single.profile.id, testProfile.id);
});

test('credential reply returns the selected auth material without logging it', () async {
  final store = InMemorySshCredentialStore();
  await store.savePassword(testProfile.id, 'secret');
  final diagnostics = <String>[];
  final bridge = SshWorkerAuthBridge(
    credentialStore: store,
    knownHostRepository: InMemorySshKnownHostRepository(),
    log: diagnostics.add,
  );

  expect(await bridge.passwordFor(testProfile), 'secret');
  expect(diagnostics, everyElement(isNot(contains('secret'))));
});
~~~

Run the focused file and expect failure.

- [ ] **Step 2: Implement auth challenge routing**

Keep SshHostKeyTrustPolicy in the UI isolate. The worker callback sends a challenge containing profile id, key type, and fingerprint bytes; the bridge invokes the existing policy and replies with a boolean. Credential callbacks request only the selected profile field. Private-key parsing with SSHKeyPair.fromPem occurs inside the worker after the bridge returns the PEM, so key parsing and handshake crypto stay off the UI isolate.

Resolve pairedRelayTunnels.targetFor(profile.id) before worker connect and pass an immutable SshWorkerDialTarget to the worker. Re-resolve it for each new worker generation.

- [ ] **Step 3: Run auth tests and existing connection tests**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_auth_bridge_test.dart test/services/ssh/ssh_client_factory_pool_test.dart test/services/ssh/ssh_transport_close_test.dart
~~~

Expected: PASS with existing direct connector tests unchanged.

- [ ] **Step 4: Commit**

~~~
git add client/lib/services/ssh/worker/ssh_worker_auth_bridge.dart client/lib/services/ssh/worker/ssh_profile_worker.dart client/lib/services/ssh/ssh_client_factory.dart client/test/services/ssh/worker/ssh_worker_auth_bridge_test.dart
git commit -m "feat(ssh): bridge worker authentication challenges"
~~~

### Task 4: Migrate storage exec and SFTP to the profile worker

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_storage_client.dart
- Create: client/test/services/ssh/worker/ssh_worker_storage_client_test.dart
- Modify: client/lib/services/ssh/ssh_client_factory.dart
- Modify: client/lib/services/storage/remote_file_store.dart
- Modify: client/lib/services/storage/remote_home_resolver.dart
- Modify: client/lib/services/storage/remote_ssh_storage_paths.dart
- Modify: client/lib/services/storage/runtime_context_resolver.dart
- Modify: client/lib/services/launch/workspace_provisioner.dart
- Modify: client/lib/services/launch/work_plane_script_runner.dart
- Modify: client/lib/services/remote/remote_cli_readiness.dart
- Modify: client/lib/services/cli/cli_installer_service.dart
- Modify: client/lib/services/ssh/event_transport_ssh_channel.dart
- Modify: direct storage call sites found with rg -n "clientForStorage\\(|sftpFor\\(" client/lib client/test --glob '*.dart'.

**Interfaces:**
- Consumes: Tasks 1–3 worker proxy and auth bridge.
- Produces: SshWorkerStorageClient.ensureConnected, run, stat, listDirectory, readChunk, writeChunk, closeStream, and SshWorkerFileChunk; SshClientFactory storage methods no longer return SSHClient/SftpClient in production paths.

- [ ] **Step 1: Write failing storage/backpressure tests**

Cover bounded reads, acknowledged writes, cancellation, and transport failure:

~~~
test('read stream never has more than the configured window in flight', () async {
  final worker = FakeSshProfileWorkerClient();
  final storage = SshWorkerStorageClient(worker, maxInFlightChunks: 4);

  final chunks = <Uint8List>[];
  await storage.readChunks('/large.bin', onChunk: (chunk) async {
    chunks.add(chunk);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  });

  expect(worker.maxObservedUnacknowledgedChunks, 4);
  expect(chunks, isNotEmpty);
});

test('failed write does not acknowledge the failed chunk', () async {
  final worker = FakeSshProfileWorkerClient(failWriteAtSequence: 2);
  final storage = SshWorkerStorageClient(worker);

  await expectLater(
    storage.writeChunks('/file', Stream.fromIterable(testChunks)),
    throwsA(isA<SshWorkerTransportException>()),
  );
  expect(worker.acknowledgedSequences, [0, 1]);
});
~~~

Run the focused test and expect failure.

- [ ] **Step 2: Implement storage worker commands**

Inside SshProfileWorker, keep one storage client/SFTP handle per profile. Implement runStorage as a bounded DTO conversion of SSHRunResult (stdout, stderr, nullable exitCode, nullable signal name). Implement metadata commands as explicit operations instead of returning SftpClient.

Implement file reads and writes with a fixed chunk size and acknowledgement window. On cancellation or profile close, close the remote SFTP file and delete the worker stream state. On timeout, invalidate the storage handle and emit the existing SshTransportClosed reason.

- [ ] **Step 3: Migrate SshClientFactory and RemoteFileStore**

Replace _pool, _sftpByProfile, and direct client lifecycle bookkeeping with worker leases while preserving hasLiveStorageClient, storagePoolChanges, runTracked, disconnectProfile, disconnectAll, and reconnect event behavior. Retain a direct connector only behind an injected test transport.

Change RemoteFileStore to call the narrow storage client. Preserve path expansion, idempotent retry, directory creation, shell quoting, and existing FsStat behavior. Replace full-file remote reads used for large transfers with the chunked API; keep small text reads bounded by the existing caller contract.

Migrate all direct consumers identified in the file list. For code that only needs an exec result, use runOnStorage; for code that needs metadata/content, use the storage facade. No migrated production caller may ask for a raw dartssh2 client.

- [ ] **Step 4: Run storage tests and Docker integration tests**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_storage_client_test.dart test/services/storage/remote_file_store_test.dart test/services/storage/runtime_context_resolver_test.dart
cd client && dart run tool/run_tests.dart --tags integration test/integration/remote_materialize_cache_docker_test.dart test/integration/artifact_chunked_transfer_docker_test.dart
~~~

Expected: focused tests PASS; integration tests PASS when Docker is available and skip cleanly otherwise.

- [ ] **Step 5: Commit**

~~~
git add client/lib/services/ssh/worker/ssh_worker_storage_client.dart client/lib/services/ssh/ssh_client_factory.dart client/lib/services/storage client/lib/services/launch/workspace_provisioner.dart client/lib/services/launch/work_plane_script_runner.dart client/lib/services/remote/remote_cli_readiness.dart client/lib/services/cli/cli_installer_service.dart client/lib/services/ssh/event_transport_ssh_channel.dart client/test/services/ssh/worker/ssh_worker_storage_client_test.dart client/test/services/storage client/test/integration/remote_materialize_cache_docker_test.dart client/test/integration/artifact_chunked_transfer_docker_test.dart
git commit -m "feat(ssh): move storage operations into profile worker"
~~~

### Task 5: Migrate member sessions and PTY output

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_member_session.dart
- Create: client/lib/services/ssh/worker/ssh_worker_output_batcher.dart
- Create: client/test/services/ssh/worker/ssh_worker_member_session_test.dart
- Create: client/test/services/ssh/worker/ssh_worker_output_batcher_test.dart
- Modify: client/lib/services/ssh/ssh_member_session.dart
- Modify: client/lib/services/terminal/ssh_pty_transport.dart
- Modify: client/lib/services/terminal/terminal_transport_factory.dart
- Modify: client/lib/services/terminal/workspace_terminal_connect_coordinator.dart
- Modify: client/lib/services/terminal/workspace_shell_connector.dart
- Modify: client/lib/cubits/chat/chat_session_shell_factory.dart
- Modify: client/lib/cubits/chat/model/chat_tab.dart

**Interfaces:**
- Consumes: Task 2 worker proxy and Task 3 auth/connection lifecycle.
- Produces: proxy-backed SshMemberSession, SshWorkerPtyChannel, and a Stream<Uint8List> that emits bounded coalesced frames while preserving write, resize, done, and close semantics.

- [ ] **Step 1: Write failing PTY and batching tests**

~~~
test('PTY output is coalesced by interval and size', () async {
  final batcher = SshWorkerOutputBatcher(
    flushInterval: const Duration(milliseconds: 10),
    maxBytes: 8,
  );
  final output = <Uint8List>[];
  batcher.output.listen(output.add);

  batcher.add(Uint8List.fromList([1, 2, 3]));
  batcher.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));
  await Future<void>.delayed(Duration.zero);

  expect(output, hasLength(1));
  expect(output.single.length, lessThanOrEqualTo(8));
  await batcher.close();
});

test('closing a member session ends output and done exactly once', () async {
  final worker = FakeSshProfileWorkerClient();
  final session = SshWorkerMemberSession(worker, 'member-1');

  await session.close();

  expect(worker.closeChannelCount, 1);
  expect(await session.done, isNotNull);
});
~~~

Use FakeAsync correctly with an injectable timer/clock rather than real sleeps in the final test implementation. Run the focused files and expect failure.

- [ ] **Step 2: Implement worker-side member and PTY ownership**

The worker maps openMember to a member client handle and openPty to a session handle. It merges stdout/stderr, sends sequence-numbered output events through SshWorkerOutputBatcher, and accepts input/resize/close commands. The worker must stop reading when the output window is exhausted and resume only after an acknowledgement.

The UI-side SshMemberSession becomes a profile/member handle wrapper. Its run and runWithResult methods return app-owned DTOs; its openPty returns a proxy PTY channel rather than SSHSession. Preserve SshMemberSession.testing through an injected fake member transport so existing pure tests do not spawn isolates.

- [ ] **Step 3: Adapt SshPtyTransport and terminal callers**

Keep TerminalTransport unchanged. Change SshPtyTransport to consume the proxy PTY channel and expose its coalesced output stream. write, resize, and close send worker commands without blocking the UI isolate. Ensure done completes with the remote exit code or the existing default behavior when no code is supplied.

Update terminal/session construction and ChatTab ownership to close proxy member leases when the terminal session is disposed. Preserve remote fullscreen timing and existing terminal observation hooks.

- [ ] **Step 4: Run PTY tests and real embedded-shell integration**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/worker/ssh_worker_member_session_test.dart test/services/ssh/worker/ssh_worker_output_batcher_test.dart test/services/terminal/ssh_pty_transport_test.dart test/services/terminal/terminal_transport_factory_test.dart
cd client && dart run tool/run_tests.dart --tags integration test/integration/embedded_shell_pty_integration_test.dart test/integration/embedded_pairing_test.dart
~~~

Expected: focused tests PASS; integration tests verify input, output, resize, exit, and close over a real embedded SSH server.

- [ ] **Step 5: Commit**

~~~
git add client/lib/services/ssh/worker/ssh_worker_member_session.dart client/lib/services/ssh/worker/ssh_worker_output_batcher.dart client/lib/services/ssh/ssh_member_session.dart client/lib/services/terminal/ssh_pty_transport.dart client/lib/services/terminal/terminal_transport_factory.dart client/lib/services/terminal/workspace_terminal_connect_coordinator.dart client/lib/services/terminal/workspace_shell_connector.dart client/lib/cubits/chat/chat_session_shell_factory.dart client/lib/cubits/chat/model/chat_tab.dart client/test/services/ssh/worker/ client/test/services/terminal/ssh_pty_transport_test.dart client/test/services/terminal/terminal_transport_factory_test.dart
git commit -m "feat(ssh): move member PTY sessions into profile worker"
~~~

### Task 6: Integrate bootstrap, reconnect, and profile lifecycle

**Files:**
- Modify: client/lib/app/app_shell.dart
- Modify: client/lib/app/app_shell.dart for manager construction and teardown
- Modify: client/lib/services/ssh/ssh_profile_connection_coordinator.dart
- Modify: client/lib/services/ssh/ssh_connection_events.dart
- Modify: client/lib/services/ssh/ssh_transport_close.dart
- Modify: client/lib/services/ssh/event_transport_ssh_channel.dart
- Modify: client/lib/services/connect/paired_relay_tunnel_registry.dart to keep dial-target resolution on the UI side of the worker boundary
- Modify: all remaining direct SSH call sites found with rg -n "SSHClient|SftpClient|SSHSession|clientForStorage\\(|sftpFor\\(|createMemberClient\\(" client/lib --glob '*.dart'.
- Test: client/test/services/ssh/ssh_profile_connection_coordinator_test.dart
- Test: client/test/cubits/ssh_connection_cubit_test.dart
- Test: client/test/pages/startup_gate_test.dart

**Interfaces:**
- Consumes: Tasks 2–5 manager, storage facade, member facade, and lifecycle events.
- Produces: one injected SshProfileWorkerManager shared by SshClientFactory, TerminalTransportFactory, remote storage, event transport, and reconnect coordinator.

- [ ] **Step 1: Add bootstrap wiring tests**

Add a test seam that asserts buildAppShell creates one worker manager and passes it to the factory/transport graph. Add coordinator tests for worker-generated storage and member close events, including one coalesced reconnect signal per profile.

~~~
test('profile worker close is forwarded once to reconnect coordinator', () async {
  final events = SshConnectionEvents();
  final coordinator = makeCoordinator(events: events);

  events.onTransportClosed?.call(
    'p1',
    const SshTransportClosed(
      reason: SshTransportCloseReason.transportError,
      plane: SshTransportPlane.storage,
    ),
    StackTrace.empty,
  );
  events.onTransportClosed?.call(
    'p1',
    const SshTransportClosed(
      reason: SshTransportCloseReason.memberSessionClosed,
      plane: SshTransportPlane.member,
    ),
    StackTrace.empty,
  );

  await settleTimers();
  expect(reconnectCalls, 1);
});
~~~

- [ ] **Step 2: Wire one manager into application bootstrap**

Construct SshProfileWorkerManager next to the existing SshClientFactory in buildAppShell. Inject the existing credential store, known-host policy bridge, relay dial-target resolver, events, and an injectable launcher. Ensure app teardown calls manager shutdown after profile services stop producing requests.

Do not add a hidden singleton. Keep the manager as an AppShell dependency or an explicitly injected service owned by SshClientFactory.

- [ ] **Step 3: Preserve reconnect and user-disconnect semantics**

Make disconnectProfile and disconnectAll invalidate the worker generation and close all storage/member channels for that profile. Keep storagePoolChanges, keepalive transitions, SshTransportCloseReason, and SshProfileConnectionCoordinator's user-disconnect latch behavior unchanged from callers' perspective.

Update event transport and remote bus code to use member/channel proxies. Reject stale worker events by generation before they reach the coordinator or terminal state.

- [ ] **Step 4: Run bootstrap and SSH regression tests**

~~~
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_connection_coordinator_test.dart test/cubits/ssh_connection_cubit_test.dart test/pages/startup_gate_test.dart test/services/ssh/ssh_client_factory_pool_test.dart test/services/ssh/ssh_transport_close_test.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

Expected: all focused tests PASS and no analyzer regressions.

- [ ] **Step 5: Commit**

~~~
git add client/lib/app/app_shell.dart client/lib/main.dart client/lib/services/ssh client/lib/services/connect/paired_relay_tunnel_registry.dart client/lib/services/terminal client/lib/services/team_bus client/lib/services/event client/lib/cubits/chat client/test/services/ssh/ssh_profile_connection_coordinator_test.dart client/test/cubits/ssh_connection_cubit_test.dart client/test/pages/startup_gate_test.dart
git commit -m "feat(ssh): integrate profile worker with app lifecycle"
~~~

### Task 7: Add performance instrumentation and measured cutover

**Files:**
- Create: client/lib/services/ssh/worker/ssh_worker_metrics.dart
- Create: client/test/services/ssh/worker/ssh_worker_metrics_test.dart
- Modify: client/lib/services/ssh/worker/ssh_profile_worker_manager.dart
- Modify: client/lib/services/ssh/worker/ssh_profile_worker_client.dart
- Modify: docs/PERFORMANCE_ANALYSIS.md with the SSH worker capture scenarios
- Create: client/test/integration/ssh_worker_performance_test.dart tagged integration and performance

**Interfaces:**
- Consumes: worker request/event boundaries from Tasks 1–6.
- Produces: counters/timers for active workers, request latency, pending-message high-water mark, terminal bytes/frame, SFTP bytes/chunk, connect/reconnect latency, and worker shutdown duration.

- [ ] **Step 1: Write metrics tests**

~~~
test('metrics records request latency and queue high-water mark', () {
  final metrics = SshWorkerMetrics();

  metrics.requestStarted('r1', DateTime.utc(2026, 1, 1));
  metrics.pendingMessagesChanged(4);
  metrics.requestCompleted('r1', DateTime.utc(2026, 1, 1, 0, 0, 0, 12));

  expect(metrics.snapshot.pendingMessageHighWaterMark, 4);
  expect(metrics.snapshot.completedRequestLatencies, [
    const Duration(milliseconds: 12),
  ]);
});
~~~

- [ ] **Step 2: Implement diagnostics-only metrics**

Record aggregate values through AppLogger/diagnostic snapshots without logging payloads. Add profile id, worker generation, plane, request id, and stream id to diagnostic context. Do not emit per-byte logs. Keep the metrics object injectable and disabled by default in release builds unless the caller explicitly supplies an enabled collector.

- [ ] **Step 3: Capture before/after scenarios**

Using docs/PERFORMANCE_ANALYSIS.md and the existing live dump tools, capture the direct-mode baseline and worker-mode candidate for:

~~~
1. sustained high-volume remote PTY output;
2. concurrent SFTP reads/writes;
3. several member sessions on one profile;
4. cold connect and reconnect;
5. idle and active worker memory.
~~~

Analyze snapshots with dart run tool/analyze_performance_json.dart ... --format summary and record UI p50/p95/p99, janky-frame count, terminal/SFTP throughput, latency, queue high-water mark, and active worker count.

- [ ] **Step 4: Commit measured cutover documentation**

~~~
git add client/lib/services/ssh/worker/ssh_worker_metrics.dart client/lib/services/ssh/worker/ssh_profile_worker_manager.dart client/lib/services/ssh/worker/ssh_profile_worker_client.dart client/test/services/ssh/worker/ssh_worker_metrics_test.dart docs/PERFORMANCE_ANALYSIS.md
git commit -m "perf(ssh): instrument profile worker performance"
~~~

### Task 8: Full verification and cleanup

**Files:**
- Modify: any migrated tests still importing raw production dartssh2 client types
- Modify: docs/DEVELOPMENT.md with worker-specific focused and integration test commands
- Modify: docs/ARCHITECTURE.md with the profile worker ownership and proxy boundary

- [ ] **Step 1: Search for forbidden production ownership**

Run:

~~~
rg -n "SSHClient|SftpClient|SSHSession" client/lib/services client/lib/cubits client/lib/pages --glob '*.dart'
~~~

Expected: dartssh2 types appear only inside client/lib/services/ssh/worker/ and explicitly documented test seams; UI-facing services use TeamPilot-owned proxy/DTO types.

- [ ] **Step 2: Run the full mandated verification**

~~~
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart
~~~

Expected: analyzer clean and full test suite green. Run the full suite once in the background when the focused loop is green, following the repository's test-loop guidance.

- [ ] **Step 3: Run real SSH smoke tests**

~~~
cd client && dart run tool/run_tests.dart --tags integration test/integration/embedded_pairing_test.dart test/integration/embedded_shell_pty_integration_test.dart
cd client && dart run tool/run_tests.dart --tags integration test/integration/remote_materialize_cache_docker_test.dart test/integration/artifact_chunked_transfer_docker_test.dart
~~~

Expected: embedded tests pass; Docker tests pass when Docker is available and skip with their existing availability guard otherwise.

- [ ] **Step 4: Commit cleanup and documentation**

~~~
git add client/lib client/test docs/DEVELOPMENT.md docs/ARCHITECTURE.md
git commit -m "docs(ssh): document profile worker boundary"
~~~

## Plan Self-Review

- Spec coverage: architecture, primitive boundary, auth bridge, storage chunking/backpressure, PTY batching, worker generations, reconnect behavior, testing, metrics, risks, and performance acceptance are covered by Tasks 1–8.
- Placeholder scan: the plan contains no unassigned or incomplete implementation step; each task names files, interfaces, tests, commands, and commit boundaries.
- Type consistency: SshWorkerRequest/Reply/Event are introduced in Task 1, consumed by the manager in Task 2, auth bridge in Task 3, storage/member proxies in Tasks 4–5, and lifecycle wiring in Task 6. SshWorkerMetrics is introduced in Task 7 and receives manager/client events defined earlier.
- Scope: the plan keeps one worker per profile, leaves terminal rendering on the UI isolate, and avoids unrelated SSH algorithm or storage-layout changes.
