# ACP Idle Reclaim + Session Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make background ACP seats participate in idle reclaim, and make every ACP (re)start resume the agent's own session (`session/load` → `session/resume` → `session/new`) instead of always starting fresh.

**Architecture:** Persist the ACP agent `sessionId` in a sidecar JSON next to the chat transcript; `AcpSessionRuntime.start` gains a `resumeSessionId` and picks load/resume/new from the negotiated capabilities, falling back to new. `TabMemberReclaimWatch` grows a second loop over `ChatTab.memberAcpRuntimes` (mixed sessions only) and hands the seat to a new `SessionLaunchService.discardAcpSeat`; restore reuses the existing member-connect funnel.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, existing ACP chat cubit / transcript, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-15-acp-idle-reclaim-and-resume-design.md` — read it first (decisions D1–D7, snapshot mapping table).

**Status: COMPLETE** — all 6 tasks landed on branch `acp-idle-reclaim` via subagent-driven development (ledger: `.superpowers/sdd/2026-10-15-acp-idle-reclaim-and-resume/progress.md`). Two deferred guards from the ledger were closed after the fact:

- `AcpAgentSession` suppression guard — `acp_session_test.dart: 'a load session drops replayed updates until the first prompt'`.
- Resume-id boundaries — `acp_session_runtime_test.dart: 'start ignores a whitespace-only resume id'` and `'…when the agent negotiates no resume'`.

## Global Constraints

- Tests ONLY through the wrapper: `cd client && dart run tool/run_tests.dart <paths>` — never raw `flutter test`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Logging via `AppLogger` (`appLogger`), never `print`. No user copy is added → no l10n/arb changes.
- Do not add `if (cli == …)` branches: the resume path is purely capability-gated.
- Reclaim scope is **mixed ACP seats only** (`isAcpChatSession` personal sessions are never reclaimed).
- ACP idle threshold = `reclaimIdleTerminalAfterSeconds * 2`; reuse the existing setting, no new one.
- Soft file-size limits: services ~600, cubits ~500 lines. If `acp_connection.dart` grows past ~430, split the establish helper into a private top-level function in the same file.
- Adding `String? resumeSessionId` to `AcpSessionRuntimeApi.start` is a **breaking interface change**: update every implementation and `implements AcpSessionRuntimeApi` fake listed in Task 2.

---

### Task 1: `AcpAgentConnection` load / resume

**Files:**
- Modify: `client/lib/services/acp/acp_connection.dart`
- Test: `client/test/services/acp/acp_connection_test.dart`

**Interfaces:**
- Consumes: existing `_PairAcpTransport`, `stubInitialize` test harness; `acpd.ClientConnection.newSession/loadSession/resumeSession`.
- Produces:
  - `AcpNegotiatedCapabilities? get negotiatedCapabilities` (nullable, non-throwing)
  - `Future<AcpAgentSession> loadSession({required String sessionId, required String cwd, List<acpd.McpServer> mcpServers = const [], Map<String, Object?> meta = const {}, Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout})`
  - `Future<AcpAgentSession> resumeSession({...same...})`

- [x] **Step 1: Write the failing tests**

Append to `acp_connection_test.dart` (reuse `agent`, `conn`, `stubInitialize`; that file already imports `dart:async`, `acpd`, `acpd_test`):

```dart
test('negotiatedCapabilities is null before initialize and non-null after', () async {
  expect(conn.negotiatedCapabilities, isNull);
  stubInitialize();
  await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');
  expect(conn.negotiatedCapabilities, isNotNull);
  expect(conn.negotiatedCapabilities!.loadSession, isFalse);
});

test('loadSession sends session/load with the stored id and returns it', () async {
  stubInitialize();
  Map<String, Object?>? seen;
  agent.connection.onRequest('session/load', (params) {
    seen = (params! as Map).cast<String, Object?>();
    return acpd.LoadSessionResponse().toJson();
  });
  await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

  final session = await conn.loadSession(sessionId: 'agent-9', cwd: '/w');

  expect(seen!['sessionId'], 'agent-9');
  expect(seen!['cwd'], '/w');
  expect(session.sessionId, 'agent-9');
});

test('resumeSession sends session/resume', () async {
  stubInitialize();
  Map<String, Object?>? seen;
  agent.connection.onRequest('session/resume', (params) {
    seen = (params! as Map).cast<String, Object?>();
    return acpd.ResumeSessionResponse().toJson();
  });
  await conn.initialize(clientName: 'teampilot', clientVersion: '1.0.0');

  final session = await conn.resumeSession(sessionId: 'agent-9', cwd: '/w');

  expect(seen!['sessionId'], 'agent-9');
  expect(session.sessionId, 'agent-9');
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart`
Expected: FAIL — `negotiatedCapabilities` / `loadSession` / `resumeSession` undefined.

- [x] **Step 3: Implement**

In `acp_connection.dart`:

1. Add the nullable getter beside `capabilities`:

```dart
/// Negotiated capabilities, or null before [initialize] completes.
AcpNegotiatedCapabilities? get negotiatedCapabilities => _capabilities;
```

2. Add an open-kind enum near the top of the file:

```dart
enum AcpSessionOpenKind { create, load, resume }
```

3. Refactor `openSession` to delegate to a private `_establish`, and add `loadSession` / `resumeSession`:

```dart
Future<AcpAgentSession> openSession({
  required String cwd,
  List<acpd.McpServer> mcpServers = const [],
  Map<String, Object?> meta = const {},
  Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
}) => _establish(
  kind: AcpSessionOpenKind.create,
  cwd: cwd,
  mcpServers: mcpServers,
  meta: meta,
  permissionTimeout: permissionTimeout,
);

Future<AcpAgentSession> loadSession({
  required String sessionId,
  required String cwd,
  List<acpd.McpServer> mcpServers = const [],
  Map<String, Object?> meta = const {},
  Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
}) => _establish(
  kind: AcpSessionOpenKind.load,
  sessionId: sessionId,
  cwd: cwd,
  mcpServers: mcpServers,
  meta: meta,
  permissionTimeout: permissionTimeout,
);

Future<AcpAgentSession> resumeSession({
  required String sessionId,
  required String cwd,
  List<acpd.McpServer> mcpServers = const [],
  Map<String, Object?> meta = const {},
  Duration permissionTimeout = AcpAgentSession.defaultPermissionTimeout,
}) => _establish(
  kind: AcpSessionOpenKind.resume,
  sessionId: sessionId,
  cwd: cwd,
  mcpServers: mcpServers,
  meta: meta,
  permissionTimeout: permissionTimeout,
);
```

4. Move the existing `openSession` body into `_establish` with two changes: the load/resume branch, and the bootstrap-suppression flag. `newSession` currently uses `_client.client.newSession(...)`; adapt:

```dart
Future<AcpAgentSession> _establish({
  required AcpSessionOpenKind kind,
  String? sessionId,
  required String cwd,
  required List<acpd.McpServer> mcpServers,
  required Map<String, Object?> meta,
  required Duration permissionTimeout,
}) async {
  final existing = _openSession;
  if (existing != null) {
    throw StateError(
      'Connection already has an open ACP session '
      '(${existing.sessionId}); dispose it before opening another.',
    );
  }
  final resuming = kind != AcpSessionOpenKind.create;
  // Only session/new replays agent updates during setup; load/resume replay
  // the whole conversation, which the app transcript already owns — do not
  // buffer it (see AcpAgentSession.suppressBootstrapUpdates).
  final earlyUpdates = <Map<String, Object?>>[];
  acpd.HandlerRegistration? earlyUpdateReg;
  if (!resuming) {
    earlyUpdateReg = _client.connection.onNotification('session/update', (
      params,
    ) {
      if (params is Map) earlyUpdates.add(Map<String, Object?>.from(params));
    });
  }
  final earlyPermissionReg = _client.connection.onRequest(
    'session/request_permission',
    _onHandshakePermission,
  );
  late final AcpAgentSession session;
  try {
    final String resolvedId;
    switch (kind) {
      case AcpSessionOpenKind.create:
        final response = await _client.client.newSession(
          acpd.NewSessionRequest(cwd: cwd, mcpServers: mcpServers, meta: meta),
        );
        resolvedId = response.sessionId;
      case AcpSessionOpenKind.load:
        await _client.client.loadSession(
          acpd.LoadSessionRequest(
            sessionId: sessionId!,
            cwd: cwd,
            mcpServers: mcpServers,
            meta: meta,
          ),
        );
        resolvedId = sessionId;
      case AcpSessionOpenKind.resume:
        await _client.client.resumeSession(
          acpd.ResumeSessionRequest(
            sessionId: sessionId!,
            cwd: cwd,
            mcpServers: mcpServers,
            meta: meta,
          ),
        );
        resolvedId = sessionId;
    }
    session = AcpAgentSession(
      connection: this,
      sessionId: resolvedId,
      permissionTimeout: permissionTimeout,
      suppressBootstrapUpdates: resuming,
    );
  } catch (_) {
    earlyPermissionReg.dispose();
    rethrow;
  } finally {
    earlyUpdateReg?.dispose();
  }
  earlyPermissionReg.dispose();
  _openSession = session;
  for (final params in earlyUpdates) {
    session.replayRawNotification(params);
  }
  for (final notice in _pendingAuth) {
    session.replayAuth(notice);
  }
  _pendingAuth.clear();
  return session;
}
```

5. Delete the old `openSession` body (now replaced by `_establish`). Keep `sessionDisposed`, `_onHandshakePermission`, etc. unchanged.

- [x] **Step 4: Update `AcpAgentSession` constructor for `suppressBootstrapUpdates`**

Modify `acp_session.dart`:

```dart
AcpAgentSession({
  required AcpAgentConnection connection,
  required this.sessionId,
  this.permissionTimeout = defaultPermissionTimeout,
  this.permissionPolicy = LaunchSecurityPolicy.fullAccess,
  bool suppressBootstrapUpdates = false,
}) : _connection = connection,
     _client = connection.acpdClient,
     _suppressBootstrap = suppressBootstrapUpdates {
  // ...existing registrations unchanged...
}
```

Add the field and the drop-latch:

```dart
/// When true, `session/update` notifications are dropped until the first
/// [prompt]. Set for load/resume sessions: the agent replays its whole
/// history, but the app transcript is the UI source of truth.
bool _suppressBootstrap;
```

In `_onSessionUpdate`, after the `_disposed` check:

```dart
if (_suppressBootstrap) return;
```

At the very start of `prompt(String text)` (before the in-flight guard):

```dart
_suppressBootstrap = false;
```

- [x] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_connection_test.dart test/services/acp/acp_session_test.dart`
Expected: PASS (existing session tests unaffected — default false).

- [x] **Step 6: Commit**

```bash
git add client/lib/services/acp/acp_connection.dart client/lib/services/acp/acp_session.dart client/test/services/acp/acp_connection_test.dart
git commit -m "feat(acp): load/resume session support on the connection"
```

---

### Task 2: `AcpSessionRuntime.start` resume selection + fallback

**Files:**
- Modify: `client/lib/services/acp/acp_session_runtime.dart`
- Modify (interface fakes — add `String? resumeSessionId`):
  - `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` (`_FakeAcpRuntime`)
  - `client/test/pages/chat/acp_runtime_for_view_test.dart`
  - `client/test/pages/chat/acp_plan_card_test.dart`
  - `client/test/pages/chat/acp_permission_card_test.dart`
  - `client/test/pages/chat/acp_ask_card_test.dart`
  - `client/test/pages/chat/session_chat_view_acp_test.dart`
- Test: `client/test/services/acp/acp_session_runtime_test.dart`

**Interfaces:**
- Consumes: `AcpAgentConnection.negotiatedCapabilities` / `loadSession` / `resumeSession` (Task 1).
- Produces: `AcpSessionRuntimeApi.start({..., String? resumeSessionId})`.

- [x] **Step 1: Write the failing tests**

Append to `acp_session_runtime_test.dart` (reuse its existing spawner/`AcpLaunchPlan` harness; the fake spawner returns an `AcpAgentConnection` built on an `acpd_test.MockAgent`, or a stub that records which acpd method was called). Cover:

```dart
test('start loads the stored session when loadSession is negotiated', () async {
  // stubInitialize with loadSession: true; agent answers session/load.
  await runtime.start(
    tool: CliTool.gemini, executable: 'gemini',
    sessionToolDir: '/t', workingDirectory: '/w',
    resumeSessionId: 'agent-9',
  );
  expect(runtime.sessionId, 'agent-9');
});

test('start falls back to session/new when loading fails', () async {
  // stubInitialize with loadSession: true; session/load returns an RpcError;
  // session/new returns 'fresh-1'.
  await runtime.start(
    tool: CliTool.gemini, executable: 'gemini',
    sessionToolDir: '/t', workingDirectory: '/w',
    resumeSessionId: 'stale',
  );
  expect(runtime.sessionId, 'fresh-1');
});

test('start uses session/new when no resume id is given', () async {
  await runtime.start(
    tool: CliTool.gemini, executable: 'gemini',
    sessionToolDir: '/t', workingDirectory: '/w',
  );
  expect(runtime.sessionId, 'fresh-1');
});
```

- [x] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart`
Expected: FAIL — `resumeSessionId` is not a parameter.

- [x] **Step 3: Implement — interface + impl**

In `acp_session_runtime.dart`, add the parameter to `AcpSessionRuntimeApi.start` and the impl:

```dart
Future<void> start({
  required CliTool tool,
  required String executable,
  required String sessionToolDir,
  required String workingDirectory,
  Map<String, String> baseEnv = const {},
  List<acpd.McpServer> mcpServers = const [],
  LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
  String? resumeSessionId,
});
```

In `AcpSessionRuntime.start`, inside the try-block, replace the unconditional `connection.openSession(...)` with a helper call:

```dart
final session = await _openSession(
  connection: connection,
  resumeSessionId: resumeSessionId,
  cwd: workingDirectory,
  mcpServers: sessionMcp,
  meta: plan.sessionNewMeta?.call(env) ?? const {},
);
```

Add the helper on `AcpSessionRuntime`:

```dart
/// Opens the session, resuming [resumeSessionId] when the agent negotiated
/// support. Any load/resume failure falls back to a fresh `session/new` — a
/// stale id must never block the user.
Future<AcpAgentSession> _openSession({
  required AcpAgentConnection connection,
  required String? resumeSessionId,
  required String cwd,
  required List<acpd.McpServer> mcpServers,
  required Map<String, Object?> meta,
}) async {
  final resumeId = resumeSessionId?.trim() ?? '';
  if (resumeId.isEmpty) {
    return connection.openSession(cwd: cwd, mcpServers: mcpServers, meta: meta);
  }
  final caps = connection.negotiatedCapabilities;
  try {
    if (caps?.loadSession ?? false) {
      return await connection.loadSession(
        sessionId: resumeId, cwd: cwd, mcpServers: mcpServers, meta: meta,
      );
    }
    if (caps?.sessionResume ?? false) {
      return await connection.resumeSession(
        sessionId: resumeId, cwd: cwd, mcpServers: mcpServers, meta: meta,
      );
    }
  } on Object catch (error) {
    AppLogger.instance.w(
      'ACP: resume of $resumeId failed ($error); opening a new session',
    );
  }
  return connection.openSession(cwd: cwd, mcpServers: mcpServers, meta: meta);
}
```

- [x] **Step 4: Update the interface fakes**

In each listed fake's `start`, add `String? resumeSessionId,` to the named parameters (default null). Mirrors the interface; no behavior change. `_FakeAcpRuntime` in the cubit test may additionally record `resumeSessionId` for Task 3.

- [x] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/pages/chat/acp_runtime_for_view_test.dart test/pages/chat/acp_ask_card_test.dart test/pages/chat/acp_permission_card_test.dart test/pages/chat/acp_plan_card_test.dart`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add client/lib/services/acp/acp_session_runtime.dart client/test
git commit -m "feat(acp): resume the agent session on start when supported"
```

---

### Task 3: Persist + replay the agent session id

**Files:**
- Create: `client/lib/services/acp/acp_agent_session_store.dart`
- Create: `client/test/services/acp/acp_agent_session_store_test.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `Filesystem`, `AcpChatRuntimeCubit` constructor, `_FakeAcpRuntime` from Task 2.
- Produces:
  - `AcpAgentSessionStore({required Filesystem fs, required String path})` with `read()/write()/clear()`
  - `AcpChatRuntimeCubit({..., AcpAgentSessionStore? agentSession})`

- [x] **Step 1: Write the failing store test**

```dart
// acp_agent_session_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_session_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips the agent session id', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    expect(await store.read(), isNull);
    await store.write('agent-9');
    expect(await store.read(), 'agent-9');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('ignores a non-v1 or garbage file', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    await fs.atomicWrite('/tp/acp-session.json', 'not json');
    expect(await store.read(), isNull);
  });
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_agent_session_store_test.dart`
Expected: FAIL — file not found.

- [x] **Step 3: Implement the store**

```dart
// acp_agent_session_store.dart
import 'dart:convert';

import '../io/filesystem.dart';

/// Sidecar persistence for one ACP session's agent-side `sessionId`.
///
/// The id is the ACP `session/new` response id, used to `session/load` the
/// same agent session on a later start. File shape: `{"v":1,"sessionId":"…"}`.
class AcpAgentSessionStore {
  AcpAgentSessionStore({required Filesystem fs, required this.path}) : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<String?> read() async {
    final raw = await _fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != 1) return null;
      final id = decoded['sessionId'];
      return (id is String && id.isNotEmpty) ? id : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String sessionId) =>
      _fs.atomicWrite(path, jsonEncode({'v': 1, 'sessionId': sessionId}));

  Future<void> clear() => _fs.atomicWrite(path, '');
}
```

- [x] **Step 4: Wire the cubit**

In `AcpChatRuntimeCubit`: add `AcpAgentSessionStore? agentSession` to the constructor and store it in `_agentSession`. In `start()`, before `_runtime.start(...)`:

```dart
final resumeId = await _agentSession?.read();
if (_closing || isClosed) return;
```

Pass `resumeSessionId: resumeId` to `_runtime.start(...)`. After a successful start (just before `emit(state.copyWith(phase: AcpChatPhase.ready))`):

```dart
final liveId = _runtime.sessionId;
if (liveId.isNotEmpty && liveId != resumeId) {
  unawaited(_agentSession?.write(liveId));
}
```

- [x] **Step 5: Write the failing cubit tests**

Append to `acp_chat_runtime_cubit_test.dart`. Extend `_FakeAcpRuntime` with `String? lastResumeSessionId;` recorded in `start`, and extend the file's `bootCubit(...)` helper with an `AcpAgentSessionStore? agentSession` parameter forwarded to the cubit constructor:

```dart
test('start resumes a stored agent session id and persists a fresh one', () async {
  final fs = InMemoryFilesystem();
  final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
  await store.write('agent-9');
  final cubit = bootCubit(agentSession: store);
  await cubit.start(
    executable: 'gemini', sessionToolDir: '/t', workingDirectory: '/w',
  );
  expect(runtime.lastResumeSessionId, 'agent-9');
  await cubit.close();
  // The fake mints 'acp-session-1' → the stale id is overwritten.
  expect(await store.read(), 'acp-session-1');
});
```

- [x] **Step 6: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_agent_session_store_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS.

- [x] **Step 7: Wire the attach path**

In `acp_runtime_attach.dart`, mirror `_transcript(...)` with a `_agentSessionStore(session, memberId:, personal:)` that returns an `AcpAgentSessionStore` at the same directory, file name `acp-session.json` / `acp-session-<memberId>.json`. Pass it into the `AcpChatRuntimeCubit(...)` construction in `_cubit(...)`:

```dart
return AcpChatRuntimeCubit(
  runtime: runtime,
  sessionId: session.sessionId,
  tool: cli,
  seatMemberId: personal ? AcpChatRuntimeCubit.acpMemberId : memberId!,
  attention: _host.agentAttentionCubit,
  transcript: _transcript(session, memberId: memberId, personal: personal),
  agentSession: _agentSessionStore(session, memberId: memberId, personal: personal),
)..ensureStrings(...);
```

- [x] **Step 8: Run the attach tests**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_runtime_attach_test.dart test/services/chat/launch/session_launch_acp_attach_test.dart`
Expected: PASS.

- [x] **Step 9: Commit**

```bash
git add client/lib/services/acp/acp_agent_session_store.dart client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart client/lib/services/chat/launch/connect/acp_runtime_attach.dart client/test
git commit -m "feat(acp): persist the agent session id and resume it"
```

---

### Task 4: Reclaim watch enumerates ACP seats

**Files:**
- Modify: `client/lib/services/chat/runtime/tab_member_reclaim_watch.dart`
- Modify: `client/lib/services/chat/runtime/tab_session_runtime_coordinator.dart`
- Test: `client/test/cubits/chat/tab_member_reclaim_watch_test.dart`

**Interfaces:**
- Consumes: `AcpChatRuntimeCubit` state (`phase`, `inTurn`, `pendingClient`), `isAcpChatSession`.
- Produces: `TabMemberReclaimWatch({..., TerminalReclaimPolicy Function()? acpPolicy, void Function(String sessionId, String memberId)? onDiscardAcpSeat})`; coordinator factory gains `onReclaimAcpSeat` + `acpIdleAfterSeconds`.

- [x] **Step 1: Write the failing tests**

In `tab_member_reclaim_watch_test.dart`, extend `_watch` with `TerminalReclaimPolicy? acpPolicy` (a 2-second policy in tests) and `void Function(String, String)? onDiscardAcpSeat`, then add:

```dart
test('reclaims an idle hidden ACP seat', () async {
  final store = ChatTabStore(storage: fakeHomeStorage());
  final tab = _tabWithBus();
  tab.persistedSession = AppSession(
    sessionId: 'sess', workspaceId: 'ws', createdAt: 1, sessionTeam: 't',
  );
  store.registerSession(tab);
  final bus = _busWith('worker-1', MemberLifecycle.running, MemberActivity.turnDoneBusWait);
  tab.teamBus = bus;
  tab.memberAcpRuntimes['worker-1'] = _readyCubit();

  final discarded = <(String, String)>[];
  var now = DateTime(2026, 8, 9, 12, 0, 0);
  final watch = _watch(
    store, onDiscard: (_, __) {}, now: () => now,
    onDiscardAcpSeat: (s, m) => discarded.add((s, m)),
    // shorter ACP threshold for the test
  );
  watch.tick();
  now = now.add(const Duration(seconds: 3));
  watch.tick();
  expect(discarded, contains(('sess', 'worker-1')));
});

test('never reclaims the selected ACP seat or a personal ACP session', () async {
  final store = ChatTabStore(storage: fakeHomeStorage());

  // Selected seat: protected via isDisplayed.
  final selected = _tabWithBus();
  selected.persistedSession = AppSession(
    sessionId: 'sess', workspaceId: 'ws', createdAt: 1, sessionTeam: 't',
  );
  selected.selectedMemberId = 'worker-1';
  store.registerSession(selected);
  selected.teamBus = _busWith('worker-1', MemberLifecycle.running, MemberActivity.turnDoneBusWait);
  selected.memberAcpRuntimes['worker-1'] = await _readyCubit();

  // Personal ACP tab: skipped entirely (D1).
  final personal = _tabWithBus();
  personal.persistedSession = AppSession(
    sessionId: 'sess', workspaceId: 'ws', createdAt: 1, sessionTeam: '', acp: true,
  );
  personal.selectedMemberId = 'sess';
  store.registerSession(personal);
  personal.memberAcpRuntimes['sess'] = await _readyCubit();

  // Launching seat: protected via shellConnecting.
  final launching = _tabWithBus();
  launching.persistedSession = AppSession(
    sessionId: 'sess', workspaceId: 'ws', createdAt: 1, sessionTeam: 't',
  );
  store.registerSession(launching);
  launching.memberAcpRuntimes['worker-1'] = _launchingCubit();

  final discarded = <(String, String)>[];
  var now = DateTime(2026, 8, 9, 12, 0, 0);
  final watch = _watch(
    store, onDiscard: (_, __) {}, now: () => now,
    onDiscardAcpSeat: (s, m) => discarded.add((s, m)),
  );
  watch.tick();
  now = now.add(const Duration(seconds: 3));
  watch.tick();

  expect(discarded, isEmpty);
});
```

`_readyCubit()` builds `AcpChatRuntimeCubit(runtime: _FakeAcpRuntime(), sessionId: 'sess', tool: CliTool.gemini)` and `await`s `start(...)` so `phase == AcpChatPhase.ready`; `_launchingCubit()` builds the same cubit **without** calling `start` so `phase == AcpChatPhase.launching`. (Reuse the `_FakeAcpRuntime` shape; if it is private to the cubit test, copy the minimal stub into this file.)

- [x] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_reclaim_watch_test.dart`
Expected: FAIL — `onDiscardAcpSeat` / `acpPolicy` are not parameters.

- [x] **Step 3: Implement the watch**

In `tab_member_reclaim_watch.dart`:

1. Import the cubit: `import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';`
2. Add constructor params + fields `TerminalReclaimPolicy Function()? _acpPolicy` and `void Function(String, String)? _onDiscardAcpSeat`.
3. In `tick()`, after the PTY loop, add:

```dart
final acpPolicy = _acpPolicy?.call();
if (acpPolicy != null) {
  for (final tab in _tabStore.openTabs) {
    final session = tab.persistedSession;
    if (session != null && isAcpChatSession(session)) continue; // D1
    for (final entry in tab.memberAcpRuntimes.entries.toList()) {
      final memberId = entry.key;
      final snapshot = _acpSnapshotFor(tab, memberId, entry.value, team);
      final key = (tab.info.id, memberId);
      if (acpPolicy.isProtected(snapshot)) {
        _idleSince.remove(key);
        continue;
      }
      final idleSince = _idleSince[key] ?? now;
      _idleSince[key] = idleSince;
      if (acpPolicy.shouldReclaim(snapshot, idleSince, now)) {
        appLogger.d(
          '[reclaim-watch] discard acp member=$memberId session=${tab.info.id} '
          'idle=${now.difference(idleSince).inSeconds}s',
        );
        _idleSince.remove(key);
        _onDiscardAcpSeat?.call(tab.info.id, memberId);
      }
    }
  }
}
```

4. Add `_acpSnapshotFor` implementing the spec table:

```dart
TerminalReclaimSnapshot _acpSnapshotFor(
  ChatTab tab,
  String memberId,
  AcpChatRuntimeCubit cubit,
  TeamProfile? team,
) {
  final phase = cubit.state.phase;
  return TerminalReclaimSnapshot(
    sessionId: tab.info.id,
    memberId: memberId,
    shellRunning: phase != AcpChatPhase.ended,
    shellConnecting: phase == AcpChatPhase.launching,
    isTeamLead: _isTeamLead(team, memberId),
    isDisplayed: tab.selectedMemberId == memberId,
    inTurn: cubit.state.inTurn || cubit.state.pendingClient != null,
    hasUnread: (tab.teamBus?.memberById(memberId)?.inbox.unreadCount ?? 0) > 0,
    isSessionPinned:
        _isSessionPinned?.call(tab.info.id) ??
        (tab.persistedSession?.pinned ?? false),
    hasActiveLeases: _seatHasActiveLeases?.call(tab.info.id, memberId) ?? false,
  );
}
```

5. In `tab_session_runtime_coordinator.dart`, add `void Function(String, String)? onReclaimAcpSeat` and `int Function()? acpIdleAfterSeconds` to the factory. `acpIdleAfterSeconds` already carries the doubled value (ChatCubit computes it). In the `TabMemberReclaimWatch(...)` construction add:

```dart
acpPolicy: acpIdleAfterSeconds == null
    ? null
    : () => TerminalReclaimPolicy(
        idleAfter: Duration(seconds: acpIdleAfterSeconds()),
      ),
onDiscardAcpSeat: onReclaimAcpSeat,
```

When `acpPolicy` is null the ACP loop is skipped (unchanged behavior for callers that do not pass an ACP threshold).

- [x] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/tab_member_reclaim_watch_test.dart`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add client/lib/services/chat/runtime/tab_member_reclaim_watch.dart client/lib/services/chat/runtime/tab_session_runtime_coordinator.dart client/test/cubits/chat/tab_member_reclaim_watch_test.dart
git commit -m "feat(reclaim): idle-discard hidden ACP seats"
```

---

### Task 5: `discardAcpSeat` + wiring

**Files:**
- Modify: `client/lib/services/chat/launch/session_launch_service.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/chat/launch/session_launch_acp_attach_test.dart` (or a new `session_launch_acp_discard_test.dart`)

**Interfaces:**
- Consumes: `ChatTab.memberAcpRuntimes`, `ChatTab.reclaimedMemberIds`, `SessionLaunchHost.clearAgentStatusSeat`.
- Produces: `SessionLaunchService.discardAcpSeat(String sessionId, String memberId)`.

- [x] **Step 1: Write the failing test**

Assert: discarding removes the cubit, adds the member to `reclaimedMemberIds`, and closes the cubit. Use the existing launch-service harness (a tab with a `memberAcpRuntimes` cubit built from the cubit-test stub):

```dart
test('discardAcpSeat closes the cubit and marks it reclaimed', () async {
  // tab.memberAcpRuntimes['worker-1'] = readyCubit;
  service.discardAcpSeat('sess', 'worker-1');
  expect(tab.memberAcpRuntimes.containsKey('worker-1'), isFalse);
  expect(tab.reclaimedMemberIds, contains('worker-1'));
  await pumpEventQueue();
  expect(readyCubit.isClosed, isTrue);
});
```

- [x] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_acp_discard_test.dart`
Expected: FAIL — `discardAcpSeat` undefined.

- [x] **Step 3: Implement**

In `session_launch_service.dart`, beside `discardMemberTerminal`:

```dart
/// Reclaims an idle ACP seat (Chrome-style discard).
///
/// Marks the seat discarded on the bus before tearing the runtime down, then
/// removes the cubit and records it as reclaimed. Closing the cubit persists
/// the transcript and the agent session id and kills the agent process; the
/// member-connect funnel re-attaches it on demand (resume).
void discardAcpSeat(String sessionId, String memberId) {
  final id = sessionId.trim();
  final mid = memberId.trim();
  if (id.isEmpty || mid.isEmpty) return;
  final tab = _tabStore.getOpenTabBySessionId(id);
  if (tab == null) return;
  final cubit = tab.memberAcpRuntimes[mid];
  if (cubit == null) return;
  tab.teamBus?.markMemberDiscarded(mid);
  tab.membersPendingConnect.remove(mid);
  tab.memberAcpRuntimes.remove(mid);
  tab.reclaimedMemberIds.add(mid);
  unawaited(cubit.close());
  _h.clearAgentStatusSeat(sessionId: tab.info.id, memberId: mid);
  _h.clearLaunchError(tab.info.id);
  _h.updateTabRunning(tab.info.id);
}
```

- [x] **Step 4: Wire ChatCubit**

In `chat_cubit.dart` where `TabSessionRuntimeCoordinator` is built (the `reclaimEnabled` / `onReclaimMember` block ~line 426):

```dart
onReclaimMember: _launchService.discardMemberTerminal,
onReclaimAcpSeat: _launchService.discardAcpSeat,
acpIdleAfterSeconds: () =>
    (_reclaimIdleTerminalAfterSeconds?.call() ?? 180) * 2,
```

- [x] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_launch_acp_discard_test.dart test/integration/member_terminal_reclaim_integration_test.dart`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add client/lib/services/chat/launch/session_launch_service.dart client/lib/cubits/chat_cubit.dart client/test
git commit -m "feat(reclaim): discard idle ACP seats and restore on demand"
```

---

### Task 6: Restore verification, integration test, docs

**Files:**
- Test: `client/test/integration/member_terminal_reclaim_integration_test.dart` (extend) or new `client/test/integration/mixed_team_acp_reclaim_integration_test.dart`
- Modify: `docs/superpowers/specs/2026-10-12-mixed-team-acp-session-design.md`
- Modify: `docs/ARCHITECTURE.md` (only if its reclaim row enumerates the protection set)

- [x] **Step 1: Write the failing integration test**

With a mixed team whose `worker-1` binding is ACP: run a turn, let the seat go idle, tick the reclaim watch, assert the cubit is gone and `isMemberTerminalReclaimed` is true; then call `ensureMemberTerminalForView('sess','worker-1')` and assert a fresh cubit is re-attached (the connect executor routes the ACP seat) and `reclaimedMemberIds` no longer contains it. Tag it `@Tags(['integration'])`.

- [x] **Step 2: Run test to verify it fails (before any rest of Task 6)**

Run: `cd client && dart run tool/run_tests.dart --tags integration test/integration/mixed_team_acp_reclaim_integration_test.dart`
Expected: FAIL if restore does not re-attach. If it already passes, keep it as the regression guard and note it.

- [x] **Step 3: Confirm the restore path**

`ensureMemberTerminalForView` already schedules a member connect for team sessions; `attachMemberAcpRuntime` re-creates the cubit because the reclaimed seat was removed from `memberAcpRuntimes` (`existing == null`), and `onConnectResult` clears `reclaimedMemberIds` on `ConnectShellResult.attached`. The whole point of Step 2 is to prove this. If Step 2 failed, the gap is one of exactly two things:

1. The restored cubit does not start in `AcpChatPhase.launching`, so the reclaim watch re-discards it before it is ready. Fix: make sure the re-attach path leaves the cubit in `launching` until `start` resolves (it does today; do not add a new flag).
2. `ensureMemberTerminalForView` bails early. Fix: it early-returns only when a running/connecting PTY shell exists — ACP seats have none, so this should not happen. Add a log and a regression assertion instead of new machinery.

Do not introduce a new restore mechanism.

- [x] **Step 4: Update docs**

Add a short paragraph to the mixed-team ACP spec noting: idle reclaim now covers hidden ACP seats (threshold = PTY ×2); the agent session id is persisted and resumed via `session/load`.

- [x] **Step 5: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add client/test docs
git commit -m "test(acp): mixed-team idle reclaim + resume integration"
```
