# Host Session Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the home-target `teampilot-runtime` the sole owner of agent PTYs, session catalog, live history, and prompt delivery so every GUI is a peer client over loopback or SSH.

**Architecture:** One length-prefixed JSON protocol. A headless `--runtime` process binds `127.0.0.1`, authenticates with a token file under `<teampilotRoot>/runtime/`, and pushes catalog/history/presence events. The Flutter GUI (`RuntimeClient`) never spawns agent PTYs. Existing `SessionLifecycleService`, `PromptDeliveryCoordinator`, TeamBus, and history tailers move into that process.

**Tech Stack:** Dart / Flutter, `dart:io` `ServerSocket` / `Socket`, existing `Filesystem` / `AppStorage` / `SessionRepository`, `dartssh2` local forward, `flutter_bloc`, `package:flutter_test` / `package:test`.

**Spec:** `docs/superpowers/specs/2026-08-28-host-session-runtime-design.md`

## Global Constraints

- No GUI-owned agent PTY. No Android `SshPtyTransport` for CLIs. No SFTP history poll. No owner/follower takeover.
- Runtime binds loopback only. Auth token lives at `<teampilotRoot>/runtime/auth`. Unknown protocol methods are errors.
- Pairing offer `v` is `2`; `v: 1` is rejected. Offer includes `runtime.port`, `runtime.socketName`, `runtime.command`.
- Last GUI disconnect does not stop agent PTYs. Explicit `stopSession` / `stopSeat` does. First `submitPrompt` on a stopped seat starts it; an explicit stop stays stopped until start or send.
- Transcripts remain durable truth. Clients render `AiMessage` events only.
- Do not switch on `CliTool` outside CLI capability implementations.
- Constructor-inject sockets, filesystem, process, and clocks. No real sshd in unit tests.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only, then `flutter gen-l10n`.
- Verify with focused `flutter test` from `client/` before any broader suite.
- Do not modify unrelated working-tree changes.
- Agent-seat idle reclaim in the GUI must not kill Runtime PTYs. `reclaimIdleTerminals` stays for workspace shell only.

## File structure

| File | Responsibility |
|------|----------------|
| `client/lib/services/runtime/runtime_protocol.dart` | Envelope, method names, error codes, JSON maps |
| `client/lib/services/runtime/runtime_framing.dart` | uint32be length + UTF-8 JSON |
| `client/lib/services/runtime/runtime_auth_store.dart` | Create/read/rotate token file |
| `client/lib/services/runtime/runtime_listener.dart` | Loopback accept, auth, dispatch |
| `client/lib/services/runtime/runtime_hub.dart` | In-process session directory, presence, fan-out |
| `client/lib/services/runtime/runtime_client.dart` | GUI/test client: req/res matching, event streams |
| `client/lib/services/runtime/runtime_supervisor.dart` | Ensure process + user service |
| `client/lib/services/runtime/pty_broker.dart` | One PTY per seat; start/stop/write/subscribe |
| `client/lib/services/runtime/history_publisher.dart` | Tail transcripts → history events |
| `client/lib/services/runtime/runtime_draft_store.dart` | Host LWW drafts |
| `client/lib/services/runtime/run_teampilot_runtime.dart` | Headless entry body |
| `client/lib/services/runtime/runtime_ssh_tunnel.dart` | SSH LocalForward to loopback Runtime |
| `client/lib/main.dart` | `main(List<String> args)` branches on `--runtime` |
| `client/lib/cubits/chat_cubit.dart` | Projection + commands; no `TerminalSession` |
| `client/lib/cubits/ai_history_seat.dart` | Buffer Runtime history events |
| `client/lib/services/connect/ssh_pairing_offer.dart` | `v: 2` + `SshRuntimeOffer` |
| `client/lib/utils/session/workspace_running_sessions.dart` | Running = live `seat.presence` |
| `client/lib/services/storage/workspace_layout.dart` | Draft paths per spec |

This is one control plane, not independent subprojects. Tasks are ordered so each leaves a testable slice. Do not ship a local-PTY fallback “until Runtime is ready”.

---

### Task 1: Protocol codec and framing

**Files:**
- Create: `client/lib/services/runtime/runtime_protocol.dart`
- Create: `client/lib/services/runtime/runtime_framing.dart`
- Test: `client/test/services/runtime/runtime_framing_test.dart`
- Test: `client/test/services/runtime/runtime_protocol_test.dart`

**Interfaces:**
- Consumes: none
- Produces:
  - `class RuntimeEnvelope { required String id; required String kind; required String method; Map<String, Object?> payload; Map<String, Object?> toJson(); factory RuntimeEnvelope.fromJson(Map<String, Object?> json); }` with `kind` ∈ `{req, res, evt, err}`
  - `abstract final class RuntimeMethod` with `hello`, `watchCatalog`, `watchSession`, `createSession`, `deleteSession`, `patchSession`, `startSeats`, `stopSession`, `stopSeat`, `submitPrompt`, `interruptSeat`, `answerQuestion`, `exitPlan`, `subscribePty`, `putDraft`, `clearDraft`, `readOlder`, `inflateAttachment`
  - `abstract final class RuntimeEvent` with `catalog.upsert`, `catalog.delete`, `seat.presence`, `history.snapshot`, `history.append`, `history.rewrite`, `history.page`, `delivery.updated`, `bus.mail`, `bus.task`, `bus.presence`, `draft.updated`, `client.viewing`, `pty.data`
  - `abstract final class RuntimeErrorCode` with `unauthenticated`, `protocolMismatch`, `unknownMethod`, `staleDraft`, `notFound`, `conflict`
  - `class RuntimeFrameCodec { Uint8List encode(RuntimeEnvelope envelope); void addBytes(Uint8List bytes); Stream<RuntimeEnvelope> get frames; }` — 4-byte big-endian length, then UTF-8 JSON. Reject frames larger than 16 MiB.

- [ ] **Step 1: Write the failing tests**

Create `client/test/services/runtime/runtime_framing_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/runtime/runtime_framing.dart';
import 'package:teampilot/services/runtime/runtime_protocol.dart';

void main() {
  test('round-trips a hello request', () async {
    final codec = RuntimeFrameCodec();
    final envelope = RuntimeEnvelope(
      id: '1',
      kind: 'req',
      method: RuntimeMethod.hello,
      payload: {'protocolVersion': 1, 'clientId': 'desktop-a'},
    );
    final frames = <RuntimeEnvelope>[];
    final sub = codec.frames.listen(frames.add);
    codec.addBytes(codec.encode(envelope));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(frames, hasLength(1));
    expect(frames.single.method, RuntimeMethod.hello);
    expect(frames.single.payload['clientId'], 'desktop-a');
  });

  test('rejects unknown method names at parse of err envelopes only by code', () {
    final err = RuntimeEnvelope.fromJson({
      'id': '1',
      'kind': 'err',
      'method': RuntimeMethod.hello,
      'payload': {'code': RuntimeErrorCode.unknownMethod},
    });
    expect(err.payload['code'], RuntimeErrorCode.unknownMethod);
  });

  test('splits concatenated frames', () async {
    final codec = RuntimeFrameCodec();
    final a = RuntimeEnvelope(id: 'a', kind: 'evt', method: RuntimeEvent.catalogUpsert, payload: {'sessionId': 's1'});
    final b = RuntimeEnvelope(id: 'b', kind: 'evt', method: RuntimeEvent.catalogUpsert, payload: {'sessionId': 's2'});
    final frames = <RuntimeEnvelope>[];
    final sub = codec.frames.listen(frames.add);
    final bytes = BytesBuilder()
      ..add(codec.encode(a))
      ..add(codec.encode(b));
    codec.addBytes(bytes.takeBytes());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(frames.map((e) => e.payload['sessionId']), ['s1', 's2']);
  });
}
```

`RuntimeMethod.hello` must be the string `'hello'`. `RuntimeEvent.catalogUpsert` must be the string `'catalog.upsert'`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_framing_test.dart --plain-name 'round-trips a hello request'`

Expected: FAIL because `runtime_framing.dart` is missing.

- [ ] **Step 3: Write minimal implementation**

`RuntimeEnvelope.fromJson` throws `FormatException` if `id`, `kind`, or `method` is missing/empty, or if `kind` is not one of the four values. `RuntimeFrameCodec.encode` writes length then `utf8.encode(jsonEncode(envelope.toJson()))`. `addBytes` buffers until a complete frame is available; do not JSON-decode a partial frame.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/runtime/runtime_framing_test.dart test/services/runtime/runtime_protocol_test.dart`

Expected: PASS. Add `runtime_protocol_test.dart` covering `fromJson` rejects unknown `kind` and missing `id`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/runtime_protocol.dart client/lib/services/runtime/runtime_framing.dart client/test/services/runtime/runtime_framing_test.dart client/test/services/runtime/runtime_protocol_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): add framed JSON protocol codec

EOF
)"
```

---

### Task 2: Auth token store

**Files:**
- Create: `client/lib/services/runtime/runtime_auth_store.dart`
- Test: `client/test/services/runtime/runtime_auth_store_test.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart` — add helpers via a small `RuntimeLayout` if workspace layout must stay workspace-only. Prefer `client/lib/services/storage/runtime_control_layout.dart` with `authFile`, `pidFile`, `listenPortFile` under `{teampilotRoot}/runtime/`.

**Interfaces:**
- Consumes: `Filesystem`
- Produces:
  - `class RuntimeControlLayout { RuntimeControlLayout({required String teampilotRoot, Filesystem? fs}); String get dir; String get authFile; String get pidFile; String get listenPortFile; }`
  - `class RuntimeAuthStore { RuntimeAuthStore({required Filesystem fs, required RuntimeControlLayout layout, String Function()? randomToken}); Future<String> ensureToken(); Future<String?> readToken(); Future<String> rotateToken(); bool matches(String offered, String expected); }`
  - Token is 32 bytes, base64url without padding. `ensureToken` creates the file with `0600` when missing and returns the existing token otherwise. `matches` is constant-time string compare.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/runtime/runtime_auth_store.dart';
import 'package:teampilot/services/storage/runtime_control_layout.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('ensureToken is stable until rotate', () async {
    final fs = InMemoryFilesystem();
    final layout = RuntimeControlLayout(teampilotRoot: '/tp', fs: fs);
    var n = 0;
    final store = RuntimeAuthStore(
      fs: fs,
      layout: layout,
      randomToken: () => 'tok-${n++}',
    );
    expect(await store.ensureToken(), 'tok-0');
    expect(await store.ensureToken(), 'tok-0');
    expect(await store.rotateToken(), 'tok-1');
    expect(await store.readToken(), 'tok-1');
  });

  test('matches rejects a different token', () {
    final store = RuntimeAuthStore(
      fs: InMemoryFilesystem(),
      layout: RuntimeControlLayout(teampilotRoot: '/tp', fs: InMemoryFilesystem()),
    );
    expect(store.matches('aaa', 'aaa'), isTrue);
    expect(store.matches('aaa', 'aab'), isFalse);
  });
}
```

Use `InMemoryFilesystem` from `client/test/support/in_memory_filesystem.dart` (same helper as other storage tests).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_auth_store_test.dart --plain-name 'ensureToken is stable until rotate'`

Expected: FAIL because `RuntimeAuthStore` is missing.

- [ ] **Step 3: Write minimal implementation**

Create `{teampilotRoot}/runtime/` before writing `auth`. Do not log the token.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/runtime/runtime_auth_store_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/runtime_control_layout.dart client/lib/services/runtime/runtime_auth_store.dart client/test/services/runtime/runtime_auth_store_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): persist loopback auth token under teampilotRoot

EOF
)"
```

---

### Task 3: Listener, hub, and two-client hello

**Files:**
- Create: `client/lib/services/runtime/runtime_hub.dart`
- Create: `client/lib/services/runtime/runtime_listener.dart`
- Create: `client/lib/services/runtime/runtime_client.dart`
- Test: `client/test/services/runtime/runtime_listener_test.dart`

**Interfaces:**
- Consumes: `RuntimeFrameCodec`, `RuntimeAuthStore`, `ServerSocket` factory
- Produces:
  - `class RuntimeHelloParams { required String clientId; required String deviceLabel; required int protocolVersion; required String token; }`
  - `class RuntimeHelloOk { static const protocolVersion = 1; }`
  - `class RuntimeListener { RuntimeListener({required Future<ServerSocket> Function(InternetAddress, int) bind, required RuntimeAuthStore auth, required RuntimeHub hub, InternetAddress? address, int port = 0}); Future<int> start(); Future<void> stop(); int get port; }`
  - `class RuntimeClient { RuntimeClient({required Future<Socket> Function() connect, required String token, required String clientId, required String deviceLabel}); Future<void> open(); Future<Map<String, Object?>> request(String method, [Map<String, Object?> payload]); Stream<RuntimeEnvelope> events({String? method}); Future<void> close(); }`
  - `class RuntimeHub` — connection registry only in this task (`register`/`unregister` by `clientId`). Catalog comes in Task 4.

Bind `InternetAddress.loopbackIPv4`. Port `0` lets the OS assign. Write the chosen port to `listenPortFile` as decimal ASCII.

`hello` payload: `{protocolVersion, clientId, deviceLabel, token}`. If `protocolVersion != 1`, respond `err` / `protocolMismatch`. If token mismatches, close after `err` / `unauthenticated`. Unknown `req.method` → `err` / `unknownMethod`.

- [ ] **Step 1: Write the failing test**

```dart
test('two clients hello on loopback', () async {
  final fs = InMemoryFilesystem();
  final layout = RuntimeControlLayout(teampilotRoot: '/tp', fs: fs);
  final auth = RuntimeAuthStore(fs: fs, layout: layout, randomToken: () => 'secret');
  await auth.ensureToken();
  final hub = RuntimeHub();
  final listener = RuntimeListener(
    bind: ServerSocket.bind,
    auth: auth,
    hub: hub,
  );
  final port = await listener.start();
  Future<RuntimeClient> open(String id) async {
    final client = RuntimeClient(
      connect: () => Socket.connect(InternetAddress.loopbackIPv4, port),
      token: 'secret',
      clientId: id,
      deviceLabel: id,
    );
    await client.open();
    return client;
  }

  final a = await open('a');
  final b = await open('b');
  final helloA = await a.request(RuntimeMethod.hello, {
    'protocolVersion': 1,
    'clientId': 'a',
    'deviceLabel': 'A',
    'token': 'secret',
  });
  expect(helloA['protocolVersion'], 1);
  await b.request(RuntimeMethod.hello, {
    'protocolVersion': 1,
    'clientId': 'b',
    'deviceLabel': 'B',
    'token': 'secret',
  });
  await a.close();
  await b.close();
  await listener.stop();
});

test('bad token is unauthenticated', () async {
  // same listener; client.open/hello with token 'nope' expects err code unauthenticated
});
```

Fold `hello` into `RuntimeClient.open` so tests after this task call `open()` only. The explicit `request(hello)` above is for the first assertion; implementation should make `open()` send hello exactly once.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_listener_test.dart --plain-name 'two clients hello on loopback'`

Expected: FAIL because `RuntimeListener` is missing.

- [ ] **Step 3: Write minimal implementation**

Serialize per-connection reads. Do not handle catalog yet. `RuntimeClient.open` must not return until hello succeeds.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/runtime/runtime_listener_test.dart`

Expected: PASS including bad-token and unknown-method cases.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/runtime_hub.dart client/lib/services/runtime/runtime_listener.dart client/lib/services/runtime/runtime_client.dart client/test/services/runtime/runtime_listener_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): accept authenticated loopback clients

EOF
)"
```

---

### Task 4: Catalog watch (two clients, no reload)

**Files:**
- Modify: `client/lib/services/runtime/runtime_hub.dart`
- Create: `client/lib/services/runtime/runtime_session_directory.dart`
- Test: `client/test/services/runtime/runtime_catalog_test.dart`
- Consumes `SessionRepository` for create/delete/list. Inject the repository; do not construct `AppStorage` inside the hub.

**Interfaces:**
- Produces:
  - `class RuntimeSessionDirectory { RuntimeSessionDirectory({required SessionRepository sessions, required Future<void> Function(RuntimeEnvelope) broadcast, FsWatcher? watcher}); Future<void> start(); Future<void> stop(); Future<Map<String, Object?>> createSession(Map<String, Object?> params); Future<void> deleteSession(String sessionId); Stream<RuntimeEnvelope> watch(); }`
  - `watchCatalog` registers the connection and immediately emits `catalog.upsert` for every current workspace and session, then live events.
  - `createSession` RPC params: `{workspaceId, sessionTeam, ...}` mapped onto existing `SessionRepository.createSession`. After disk write, broadcast `catalog.upsert` with `AppSession.toJson()`.
  - `deleteSession` broadcasts `catalog.delete` `{sessionId}`.
  - When `Filesystem` is `FsWatcher`, watch `workspace/` and re-read on change so an in-process writer still fans out if another Runtime is not involved (single Runtime is the writer; watch is for crash-consistency and tests using the repo directly).

- [ ] **Step 1: Write the failing test**

```dart
test('create on client A appears on client B without reload', () async {
  // start listener+hub with a real SessionRepository on InMemoryFilesystem + setUpTestAppStorage if required
  final eventsB = <String>[];
  b.events(method: RuntimeEvent.catalogUpsert).listen((e) {
    eventsB.add(e.payload['sessionId'] as String? ?? '');
  });
  await b.request(RuntimeMethod.watchCatalog);
  final created = await a.request(RuntimeMethod.createSession, {
    'workspaceId': workspace.workspaceId,
  });
  final id = created['sessionId'] as String;
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(eventsB, contains(id));
});
```

Use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `client/test/support/post_frame_test_harness.dart` if `SessionRepository` needs `AppStorage`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_catalog_test.dart --plain-name 'create on client A appears on client B without reload'`

Expected: FAIL (`unknownMethod` or missing directory).

- [ ] **Step 3: Write minimal implementation**

Hub routes `watchCatalog`, `createSession`, `deleteSession`, `patchSession`. `patchSession` calls existing session update helpers (rename/pin) and upserts.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/runtime/runtime_catalog_test.dart`

Expected: PASS. Include delete-fanout and watch-emits-existing-snapshot.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/runtime_hub.dart client/lib/services/runtime/runtime_session_directory.dart client/test/services/runtime/runtime_catalog_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): push session catalog to every client

EOF
)"
```

---

### Task 5: Headless `--runtime` entry and supervisor

**Files:**
- Create: `client/lib/services/runtime/run_teampilot_runtime.dart`
- Create: `client/lib/services/runtime/runtime_supervisor.dart`
- Modify: `client/lib/main.dart` — `void main(List<String> args) async { if (args.contains('--runtime')) { await runTeamPilotRuntime(args); return; }` then existing GUI body.
- Test: `client/test/services/runtime/runtime_supervisor_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> runTeamPilotRuntime(List<String> args, {RuntimeListener Function()? listenerFactory})` — init logging + `AppPaths`/`AppStorage` for native home (Runtime always executes *on* the home machine). No `runApp`. Await listener; exit on SIGINT/SIGTERM (`ProcessSignal`) in production; tests call `stop`.
  - `class RuntimeSupervisor { RuntimeSupervisor({required Future<int?> Function() readPort, required Future<bool> Function(int port) canConnect, required Future<void> Function() spawn, required Duration pollInterval}); Future<int> ensure(); }`
  - `ensure`: if `canConnect(port)` succeeds, return port; else `spawn()` (in tests a callback that starts `RuntimeListener`; in production `Process.start(Platform.resolvedExecutable, ['--runtime'])` or the advertised command) then poll until connectable. Timeout 15s then throw.
  - User-service install (`systemd --user` unit writing `ExecStart=` + `%h/.local/share/com.hhoa.teampilot` note) is part of this task for Linux; macOS launchd plist and Windows logon task in the same supervisor with platform branches. Tests inject a `RuntimeServiceInstaller` fake and assert `install()` is invoked once from `ensure(installService: true)`.

Do not initialize `window_manager`, Alacritty Rust, or Google Fonts on the runtime path.

- [ ] **Step 1: Write the failing supervisor test**

```dart
test('ensure starts a spawn when nothing listens', () async {
  var spawned = 0;
  var port = 0;
  final supervisor = RuntimeSupervisor(
    readPort: () async => port == 0 ? null : port,
    canConnect: (p) async => p == port && port != 0,
    spawn: () async {
      spawned++;
      port = 43100;
    },
    pollInterval: Duration.zero,
  );
  expect(await supervisor.ensure(), 43100);
  expect(spawned, 1);
  expect(await supervisor.ensure(), 43100);
  expect(spawned, 1);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_supervisor_test.dart --plain-name 'ensure starts a spawn when nothing listens'`

Expected: FAIL

- [ ] **Step 3: Implement supervisor + main branch**

`runTeamPilotRuntime` must be importable without pulling `MaterialApp`. Keep it free of `pages/` imports.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/runtime_supervisor_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/main.dart client/lib/services/runtime/run_teampilot_runtime.dart client/lib/services/runtime/runtime_supervisor.dart client/test/services/runtime/runtime_supervisor_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): add headless --runtime entry and supervisor

EOF
)"
```

---

### Task 6: Pairing offer v2

**Files:**
- Modify: `client/lib/services/connect/ssh_pairing_offer.dart`
- Modify: `client/lib/services/connect/connect_agent.dart` (mint `v: 2` + runtime block from listener port + `Platform.resolvedExecutable`)
- Modify every test fixture that builds `SshPairingOffer(v: 1, …)` listed by `rg "v: 1" client/test client/lib/services/connect`
- Test: extend `client/test/services/connect/ssh_pairing_offer_test.dart`

**Interfaces:**
- Produces:
  - `class SshRuntimeOffer { required int port; required String socketName; required String command; Map<String, Object?> toJson(); factory fromJson }`
  - `SshPairingOffer.runtime` required. `fromJson` throws `SshPairingOfferFormatException` if `v != 2` or `runtime` missing/invalid.
  - Constant `SshPairingOffer.currentVersion = 2`.

- [ ] **Step 1: Write the failing codec tests**

Replace the existing `v: 1` happy-path test with `v: 2` plus:

```dart
test('rejects v1 offers', () {
  expect(
    () => SshPairingOffer.fromJson({'v': 1, 'hostId': 'AbCdEf0123_-xyZ9', /* rest valid v1 shape */}),
    throwsA(isA<SshPairingOfferFormatException>()),
  );
});

test('round-trips runtime', () {
  final offer = SshPairingOffer(/* … */, runtime: SshRuntimeOffer(port: 43100, socketName: 'teampilot-runtime', command: '/opt/teampilot --runtime'));
  final decoded = SshPairingOffer.fromJson(offer.toJson());
  expect(decoded.runtime.port, 43100);
  expect(decoded.runtime.command, '/opt/teampilot --runtime');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/connect/ssh_pairing_offer_test.dart --plain-name 'rejects v1 offers'`

Expected: FAIL (decoder still accepts v1 or lacks `runtime`).

- [ ] **Step 3: Implement and update ConnectAgent mint**

Include `runtime` in both `toJson` and `_toQrJson`. Keep QR compact: `runtime: {port, command}` is enough in QR; `socketName` may be omitted in QR and defaulted to `teampilot-runtime` on decode.

- [ ] **Step 4: Run pairing tests**

Run: `cd client && flutter test test/services/connect test/pages/connect test/cubits/connect_cubit_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/connect client/test/services/connect client/test/pages/connect client/test/cubits/connect_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(connect): require pairing v2 with runtime reachability

EOF
)"
```

---

### Task 7: SSH tunnel to Runtime (Android / remote home)

**Files:**
- Create: `client/lib/services/runtime/runtime_ssh_tunnel.dart`
- Test: `client/test/services/runtime/runtime_ssh_tunnel_test.dart`
- Modify: GUI home-bind path in `client/lib/app/app_shell.dart` (after `applyAndroidSshConnectHome`, `RuntimeSupervisor.ensure` via tunnel, then `RuntimeClient.connect` to the local forwarded port)

**Interfaces:**
- Produces:
  - `class RuntimeSshTunnel { RuntimeSshTunnel({required Future<Stream<int>> Function(int remotePort) forwardLocal;}); Future<int> open(int runtimePort); Future<void> close(); }`
  - `forwardLocal` is injected. Production adapter uses dartssh2 local-to-remote forward to `127.0.0.1:runtimePort`. Tests pass a fake that returns a local ephemeral port backed by an in-process `RuntimeListener`.

- [ ] **Step 1: Write the failing test**

```dart
test('client with only a tunnel factory never opens a PTY transport', () async {
  final openedPty = <String>[];
  // RuntimeClient + tunnel fake; a spy TerminalTransportFactory must not be invoked.
  expect(openedPty, isEmpty);
});
```

Also test `open` returns the local port the fake forward bound.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_ssh_tunnel_test.dart --plain-name 'client with only a tunnel factory never opens a PTY transport'`

Expected: FAIL

- [ ] **Step 3: Implement tunnel wrapper**

Do not call `TerminalTransportFactory` from this file.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/runtime_ssh_tunnel_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/runtime_ssh_tunnel.dart client/test/services/runtime/runtime_ssh_tunnel_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): tunnel Android SSH to loopback runtime

EOF
)"
```

---

### Task 8: PtyBroker, presence, start/stop

**Files:**
- Create: `client/lib/services/runtime/pty_broker.dart`
- Create: `client/lib/services/runtime/seat_presence.dart`
- Modify: `client/lib/services/runtime/runtime_hub.dart` — route `startSeats`, `stopSession`, `stopSeat`, `subscribePty`
- Test: `client/test/services/runtime/pty_broker_test.dart`
- Test: `client/test/services/runtime/runtime_presence_test.dart`

**Interfaces:**
- Produces:
  - `enum SeatPresenceKind { idle, working, waiting, stopped, interrupted }`
  - `class SeatKey { required String sessionId; required String memberId; }`
  - `abstract interface class SeatProcess { Future<void> start(); Future<void> stop(); void write(Uint8List data); Stream<Uint8List> get output; bool get isAlive; }`
  - `class PtyBroker { PtyBroker({required Future<SeatProcess> Function(SeatKey key) spawn, required void Function(SeatKey, SeatPresenceKind) onPresence}); Future<void> startSeats(String sessionId, List<String> memberIds); Future<void> stopSession(String sessionId); Future<void> stopSeat(SeatKey key); void write(SeatKey key, Uint8List data); Stream<Uint8List> subscribePty(SeatKey key); SeatPresenceKind presence(SeatKey key); }`
  - Default presence is `stopped`. After `startSeats`, `idle` until the event plane marks working. `stop*` → `stopped` and `SeatProcess.stop`. Last `RuntimeClient` disconnect must **not** call `stopSession`.
  - `subscribePty` fans out `pty.data` events `{sessionId, memberId, b64}` to that connection only.

- [ ] **Step 1: Write the failing tests**

```dart
test('start on A shows running on B; stop on B stops A', () async {
  // fake SeatProcess per key, two RuntimeClients
  await a.request(RuntimeMethod.startSeats, {'sessionId': 's1', 'memberIds': ['m']});
  // B watchCatalog or a dedicated presence subscription: watchSession also in task 9; for now hub broadcasts seat.presence to all connections
  expect(await presenceOf(b, 's1', 'm'), SeatPresenceKind.idle.name);
  await b.request(RuntimeMethod.stopSession, {'sessionId': 's1'});
  expect(await presenceOf(a, 's1', 'm'), SeatPresenceKind.stopped.name);
});

test('last client disconnect keeps the fake PTY alive', () async {
  await a.request(RuntimeMethod.startSeats, {'sessionId': 's1', 'memberIds': ['m']});
  var stopped = false;
  // fake SeatProcess.stop sets stopped=true
  await a.close();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  expect(stopped, isFalse);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/runtime_presence_test.dart --plain-name 'start on A shows running on B'`

Expected: FAIL

- [ ] **Step 3: Implement broker with injected spawn**

Do not import Flutter widgets. Production `spawn` in Task 9 wraps `TerminalSession` / launch pipeline.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/pty_broker_test.dart test/services/runtime/runtime_presence_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/pty_broker.dart client/lib/services/runtime/seat_presence.dart client/lib/services/runtime/runtime_hub.dart client/test/services/runtime/pty_broker_test.dart client/test/services/runtime/runtime_presence_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): broker seats and broadcast presence

EOF
)"
```

---

### Task 9: Wire launch pipeline into PtyBroker

**Files:**
- Modify: `client/lib/services/runtime/run_teampilot_runtime.dart` — construct `CliToolRegistry.builtIn()`, `SessionLifecycleService`, `SessionLaunchService` internals needed to spawn, `TeammateBusMcpGateway`, `AgentEventGateway` / `PromptDeliveryCoordinator` as they exist under `client/lib/services/prompt_delivery/` and `client/lib/services/agent_runtime/`
- Create: `client/lib/services/runtime/lifecycle_seat_process.dart` — `SeatProcess` over `TerminalSession`
- Test: `client/test/services/runtime/lifecycle_seat_process_test.dart` with the existing terminal fakes from `client/test/integration/support/` or launch unit fakes — **no live CLI binary**

**Interfaces:**
- Consumes: `SessionLifecycleService.prepareLaunch`, `TerminalSession.connect`
- Produces: `Future<SeatProcess> lifecycleSpawn(SeatKey key, {required AppSession session, required TeamMemberConfig? member})`
- Member placement SSH is opened here (existing `SshPtyTransport` inside Runtime), never in the Android GUI.
- Crash reconcile on Runtime start: for each session with persisted started seats, probe pid; if dead, emit `interrupted` and do not re-paste (`PromptDeliveryCoordinator` restore → `submittedUnknown`).

- [ ] **Step 1: Write the failing test**

```dart
test('member placement SSH is opened by Runtime spawn, not the GUI client', () async {
  final sshOpens = <String>[];
  // lifecycleSpawn with a fake transport factory that records opens
  // RuntimeClient.startSeats triggers spawn
  // A dummy GUI RuntimeClient has no transport factory
  expect(sshOpens, isNotEmpty);
});
```

Use constructor injection on `lifecycleSpawn` for the transport factory.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/lifecycle_seat_process_test.dart --plain-name 'member placement SSH is opened by Runtime spawn'`

Expected: FAIL

- [ ] **Step 3: Implement `LifecycleSeatProcess`**

Copy the connect path from `SessionLaunchService` / `SessionShellConnector` into Runtime-owned types. Delete GUI calls in Task 12, not yet.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/lifecycle_seat_process_test.dart`

Expected: PASS. Add interrupted-on-dead-pid case.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/lifecycle_seat_process.dart client/lib/services/runtime/run_teampilot_runtime.dart client/test/services/runtime/lifecycle_seat_process_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): spawn seats through session lifecycle

EOF
)"
```

---

### Task 10: HistoryPublisher

**Files:**
- Create: `client/lib/services/runtime/history_publisher.dart`
- Modify: hub `watchSession`, `readOlder`, `inflateAttachment`
- Test: `client/test/services/runtime/history_publisher_test.dart`

**Interfaces:**
- Consumes: `AiHistoryLoader` / incremental tailer + `AiHistoryCapability` (existing)
- Produces:
  - `watchSession` payload `{sessionId, memberId?, resumeToken?}` → `history.snapshot` then `history.append` / `history.rewrite`
  - `history.append` payload `{sessionId, memberId, message: aiMessageToJson}` — reuse the JSON the UI already uses if present; otherwise define `Map<String, Object?> aiMessageToWire(AiMessage m)` next to the publisher and the inverse in the GUI seat
  - Streaming assistant: same `message.id` on subsequent appends; GUI merges
  - File compaction → `history.rewrite` then a fresh snapshot
  - `readOlder` → `history.page`
  - Reconnect with `resumeToken`: snapshot if token unknown; otherwise replay from token

- [ ] **Step 1: Write the failing tests**

```dart
test('streamed assistant merges on both clients with one message id', () async {
  // publisher driven by a fake tailer that emits two AiMessages with the same id
  final idsA = <String>[];
  final idsB = <String>[];
  // both watchSession
  // fake tailer appends
  expect(idsA.toSet(), {'asst-1'});
  expect(idsB.toSet(), {'asst-1'});
});

test('history rewrite replaces snapshot instead of corrupt tail merge', () async {
  // append m1, then rewrite, snapshot contains only m2
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/history_publisher_test.dart --plain-name 'streamed assistant merges on both clients with one message id'`

Expected: FAIL

- [ ] **Step 3: Implement publisher**

Do not have the GUI call `AiHistoryLiveRefreshController`. That deletion is Task 12.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/history_publisher_test.dart`

Expected: PASS including reconnect-snapshot-includes-new-lines (spec test 5) using a fake tailer that grows after disconnect.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/history_publisher.dart client/lib/services/runtime/runtime_hub.dart client/test/services/runtime/history_publisher_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): publish canonical history events to watchers

EOF
)"
```

---

### Task 11: submitPrompt, delivery, host drafts

**Files:**
- Create: `client/lib/services/runtime/runtime_draft_store.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart` — `sessionDraftFile(workspaceId, sessionId, memberId)` → `sessions/{sessionId}/drafts/{memberId}.json`; `landingDraftFile(workspaceId)` → `workspace/workspaces/{id}/drafts/landing.json`. Remove `compose-drafts.json` helper.
- Modify: hub for `submitPrompt`, `putDraft`, `clearDraft`, `interruptSeat`, `answerQuestion`, `exitPlan`
- Modify: `client/lib/services/compose/compose_draft_store.dart` — become a client wrapper around `RuntimeClient` **or** delete and call Runtime from the cubit. Prefer Runtime-only store in this package used by the hub; GUI uses RPC.
- Delete device-local write path from `ComposeDraftCache` persistence (cache may remain in-memory for widgets, hydrated from `draft.updated`)
- Test: `client/test/services/runtime/runtime_submit_test.dart`
- Test: `client/test/services/runtime/runtime_draft_store_test.dart`

**Interfaces:**
- `submitPrompt` payload `{sessionId, memberId, text, deliveryId, attachments?}`. If seat `stopped` because it never started, auto `startSeats` then deliver. If seat `stopped` after explicit `stopSession`, still auto-start on send (spec: first send auto-starts; explicit stop stays stopped until start **or send** — send counts). Deduplicate by `deliveryId`.
- Wire `PromptDeliveryCoordinator` as the only automated writer (`PtyBroker.write` behind `PromptDeliveryCommands`).
- Draft JSON `{text, rev, clientId, updatedAt}`. `putDraft` rejects `rev != current+1` with `staleDraft` and returns the host document. Success broadcasts `draft.updated`. Successful submit `clearDraft`.

- [ ] **Step 1: Write the failing tests**

```dart
test('concurrent submitPrompt on one seat serializes to one unconfirmed delivery', () async {
  // two clients same delivery wait; coordinator fake allows one in-flight
});

test('stale draft rev is rejected and other client sees draft.updated', () async {
  await a.request(RuntimeMethod.putDraft, {'sessionId': 's', 'memberId': 'm', 'text': 'hi', 'rev': 1, 'clientId': 'a'});
  expect(
    () => a.request(RuntimeMethod.putDraft, {'sessionId': 's', 'memberId': 'm', 'text': 'no', 'rev': 1, 'clientId': 'a'}),
    throwsA(/* err staleDraft */),
  );
  final seen = <String>[];
  b.events(method: RuntimeEvent.draftUpdated).listen((e) => seen.add(e.payload['text'] as String));
  await a.request(RuntimeMethod.putDraft, {'sessionId': 's', 'memberId': 'm', 'text': 'ok', 'rev': 2, 'clientId': 'a'});
  expect(seen, contains('ok'));
});
```

Include event-plane restore: Runtime restart after `submitIssued` → `submittedUnknown`, no second write (reuse coordinator tests; call them from a Runtime restart fake).

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/runtime/runtime_draft_store_test.dart test/services/runtime/runtime_submit_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement**

Do not write drafts through the old `compose-drafts.json` document.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime/runtime_draft_store_test.dart test/services/runtime/runtime_submit_test.dart test/services/prompt_delivery/`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/runtime/runtime_draft_store.dart client/lib/services/storage/workspace_layout.dart client/lib/services/compose client/lib/services/runtime/runtime_hub.dart client/test/services/runtime/runtime_draft_store_test.dart client/test/services/runtime/runtime_submit_test.dart
git commit -m "$(cat <<'EOF'
feat(runtime): submit prompts and LWW host drafts

EOF
)"
```

---

### Task 12: GUI is a Runtime projection

**Files:**
- Modify: `client/lib/app/app_shell.dart` — after home bind, `RuntimeSupervisor.ensure` + `RuntimeClient.open` + `watchCatalog`; provide `RuntimeClient` via `RepositoryProvider`
- Modify: `client/lib/cubits/chat_cubit.dart` — catalog from Runtime events; `requestOpenSession` = local tab + `watchSession` (never `TerminalSession.connect`); `submit` = `submitPrompt`; stop = `stopSession`; remove import of `terminal_session.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart` — apply snapshot/append/rewrite; remove `AiHistoryLoader` disk reads
- Modify: `client/lib/utils/session/workspace_running_sessions.dart` — `workingSessionIds` from presence `working|waiting`; `openTabSessionIds` replaced by presence `idle|working|waiting` (live seats). Signature:

```dart
List<AppSession> workspaceRunningSessions({
  required List<AppSession> sessions,
  required Set<String> liveSessionIds,
});
```

Update `RunningSessionIds.fromWorkspace` and `workspace_sidebar.dart`.
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` — drop `connectImmediately` / `openExistingSessionStartsTerminal`
- Modify: `client/lib/cubits/chat/model/session_open_request.dart` — remove `connectImmediately` and `preserveWorkbenchView` terminal forcing
- Modify: `client/lib/models/session_preferences.dart` and settings UI — delete `openExistingSessionStartsTerminal`
- Modify: `client/lib/pages/chat/session_chat_view.dart` — remove `AiHistoryLiveRefreshController`
- Test: rewrite `client/test/cubits/chat_cubit_pod_registry_test.dart` and history tests to use a fake `RuntimeClient`
- Test: `client/test/cubits/chat_cubit_runtime_test.dart` — `ChatCubit` constructed with fake Runtime has no `TerminalSession` field access (grep in test: cubit type should not require a session shell factory)

**Interfaces:**
- `ChatCubit` constructor takes `RuntimeClient runtime` (or a narrow `SessionRuntimeApi`). Delete `ChatSessionShellFactory` usage for agent seats. Workspace shell terminals stay on `WorkspaceTerminalRegistry` (not agent Runtime).

- [ ] **Step 1: Write the failing cubit test**

```dart
test('ChatCubit with RuntimeClient has no TerminalSession registry', () async {
  final runtime = FakeRuntimeClient();
  final cubit = /* harness */;
  expect(cubit, isA<ChatCubit>());
  // requestOpenSession does not call a captured TerminalSession.connect
  expect(runtime.startedSeats, isEmpty);
  await cubit.requestOpenSession(SessionOpenRequest(session: session, /* no connectImmediately */));
  expect(runtime.watchedSessions, contains(session.sessionId));
  expect(runtime.startedSeats, isEmpty);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat_cubit_runtime_test.dart --plain-name 'ChatCubit with RuntimeClient has no TerminalSession registry'`

Expected: FAIL (still connects locally).

- [ ] **Step 3: Cut ChatCubit over**

Keep file-size limits: if `chat_cubit.dart` grows, extract `ChatRuntimeProjection` in `client/lib/cubits/chat/chat_runtime_projection.dart`.

- [ ] **Step 4: Run focused tests**

Run: `cd client && flutter test test/cubits/chat_cubit_runtime_test.dart test/cubits/chat_cubit_pod_registry_test.dart test/utils/session/workspace_running_sessions_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart`

Expected: PASS. Fix every compile error from removed fields.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits client/lib/pages client/lib/models/session_preferences.dart client/lib/utils/session client/lib/app/app_shell.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test
git commit -m "$(cat <<'EOF'
feat(chat): drive sessions from RuntimeClient instead of local PTY

EOF
)"
```

Run `flutter gen-l10n` if arb keys changed (reconnect CTA, “also on {device}”).

---

### Task 13: Delete GUI agent-PTY paths

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart` — GUI must not spawn; either delete agent connect methods or turn them into Runtime RPCs already done in Task 12. Remove dead code.
- Modify: `client/lib/app/app_shell.dart` — do not pass `TerminalTransportFactory` into Chat/session launch. Factory remains for **workspace shell** only.
- Delete usages of `AiHistoryLiveRefreshController` (file may remain until unused, then delete `client/lib/services/session/ai_history_live_refresh_controller.dart` and its test).
- Android: `applyAndroidSshConnectHome` stays; after home bind only tunnel + RuntimeClient.
- Test: `client/test/services/runtime/android_runtime_path_test.dart` asserting a documented `AgentLaunchPort` typedef used by GUI is a Runtime RPC, not `SshPtyTransport`.

- [ ] **Step 1: Write the failing test**

```dart
test('Android home bind path does not construct SshPtyTransport for agents', () {
  // static analysis style: a small AppShell helper `bindHomeRuntime` return type
  // Fake that records TransportFactory.agentCalls
  expect(factory.agentCalls, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/runtime/android_runtime_path_test.dart`

Expected: FAIL or compile until helper exists.

- [ ] **Step 3: Remove dead launch/history-poll code**

Update `AGENTS.md` bootstrap and terminal-transport tables: agent CLIs are Runtime-owned; Android SSH is filesystem + Runtime tunnel.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime test/cubits/chat_cubit_runtime_test.dart test/pages/connect`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib client/test AGENTS.md docs/workspace-storage-layout.md
git commit -m "$(cat <<'EOF'
refactor: remove GUI agent PTY ownership

EOF
)"
```

---

### Task 14: TeamBus, automations, Connect host-side, reconnect UX

**Files:**
- Modify: `run_teampilot_runtime.dart` — start `TeammateBusMcpGateway`, `AutomationScheduler` + dispatcher that calls Runtime `startSeats`/`submitPrompt` instead of GUI `requestOpenSession`
- Modify: `client/lib/services/connect/connect_agent.dart` — used from Runtime process; GUI cubit talks via Runtime RPCs `connect.startQr`, `connect.offer` **or** GUI still instantiates ConnectAgent only when it *is* the local Runtime (desktop in-process). Decision: **ConnectAgent runs only inside the Runtime process.** GUI Connect page is a Runtime client of methods `connect.getOffer`, `connect.setPolicy`, `connect.revokeDevice`. Add those methods to `RuntimeMethod` and hub.
- Modify: `client/lib/pages/connect/` to use Runtime RPCs
- l10n: Runtime down → blocking reconnect + start-service CTA (`runtimeUnreachableTitle`, `runtimeUnreachableAction`)
- Test: `client/test/services/runtime/runtime_connect_rpc_test.dart`
- Test: `client/test/services/runtime/runtime_automation_dispatch_test.dart` — dispatcher does not import `ChatCubit`

**Interfaces:**
- Automation `requestOpenSession` dependency becomes `RuntimeClient.request(createSession|startSeats|submitPrompt)`.
- Home switch: `RuntimeClient.close()`, rebind `AppStorage`, `ensure` that home’s Runtime, `watchCatalog`.

- [ ] **Step 1: Write failing tests**

```dart
test('automation dispatcher starts seats through RuntimeClient', () async {
  final runtime = FakeRuntimeClient();
  // dispatch a matching rule
  expect(runtime.startedSessions, contains('…'));
});

test('connect QR offer is served by Runtime method not a GUI-owned listener', () async {
  final offer = await runtime.request('connect.getOffer');
  expect(offer['v'], 2);
  expect(offer['runtime'], isNotNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/runtime/runtime_automation_dispatch_test.dart test/services/runtime/runtime_connect_rpc_test.dart`

Expected: FAIL

- [ ] **Step 3: Implement**

GUI `ConnectCubit` wraps Runtime RPCs. Desktop-only widgets remain; they just do not construct `ConnectAgent` themselves.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/runtime test/pages/connect test/cubits/connect_cubit_test.dart test/services/automation`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib client/test client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "$(cat <<'EOF'
feat(runtime): own TeamBus, automations, and Connect host

EOF
)"
```

---

## Spec coverage

| Spec section | Task |
|--------------|------|
| Loopback listener, token auth, protocol v1 | 1–3 |
| Catalog push, no hydrate-once | 4 |
| `--runtime`, supervisor, user service | 5 |
| Pairing v2 `runtime` object | 6 |
| Android SSH is tunnel only | 7, 13 |
| Peer GUIs, no takeover, last client keeps PTY | 8 |
| Lifecycle spawn, placement SSH in Runtime | 9 |
| `AiMessage` push, rewrite, resumeToken | 10 |
| `submitPrompt`, delivery, LWW drafts | 11 |
| ChatCubit projection, Running from presence, delete history-review dual mode | 12 |
| Delete GUI agent PTY / live refresh poll | 13 |
| TeamBus, automations, Connect in Runtime, reconnect UX | 14 |
| Event plane interior / no re-paste on restart | 9, 11 |
| Files/Git stay on home Filesystem | never remoted (no task) |
| Optional `subscribePty` | 8 |
| `client.viewing` | 12 (`watchSession` registers viewing; hub broadcasts) |
| Headless work machine | 5 + 7 |

## Placeholder scan

No TBD. Filesystem tests use `InMemoryFilesystem` from `client/test/support/in_memory_filesystem.dart`.

## Type consistency

- `RuntimeMethod.*` and `RuntimeEvent.*` strings are defined in Task 1 and reused everywhere.
- `RuntimeClient.request` / `events` from Task 3.
- `SeatKey`, `SeatPresenceKind`, `PtyBroker` from Task 8.
- `SessionOpenRequest` loses `connectImmediately` in Task 12.
- Draft `rev` is `int` starting at 1 on first put.

---

After this plan ships, the acceptance walk (phone start → desktop see Running → send from desktop → close desktop → phone still live → stop from either) is a manual check on one home target with pairing v2. Unit tests cover the protocol and fan-out; they do not require a physical phone.
