# Teammate-Bus MCP Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-session loopback `TeammateBusMcpServer` instances with one app-wide MCP gateway that routes requests to per-session `TeammateBusMcpHandler` instances via `sessionId`, so all local/remote members share a fixed HTTP endpoint (and one shared raw-socket port for long-blocking remote relays).

**Architecture:** Introduce `TeammateBusMcpGateway` (singleton, started from `app_shell.dart`) owning the sole loopback HTTP listener (`/mcp`, `/idle`) plus one loopback raw-socket listener. `TeammateBusSessionRegistry` maps `sessionId → TeammateBusMcpHandler` for local routing and `token → sessionId` for remote auth. `TabTeamBusCoordinator.installBusForTab` still creates one `TeamBus` + handler per mixed session, but registers/unregisters with the gateway instead of `HttpServer.bind(0)` per tab. `TeammateBusMcpServer` HTTP/SSE logic moves into a reusable delegate used by the gateway; per-tab `ChatTab.mcpServer` is removed.

**Tech Stack:** Dart 3 / Flutter (`client/`), `dart:io` HttpServer, existing `TeammateBusMcpHandler`, `BusRawSocketServer` framing, `tools/teammate_bus_bridge` stdio bridge.

**Design input:** User decision (2026-07-02): sessionId → TeamBus instance + centralized request dispatch; avoid N loopback ports.

---

## File map (create / modify)

| File | Responsibility |
|------|----------------|
| `client/lib/services/team_bus/mcp/teammate_bus_session_registry.dart` | **Create.** `sessionId` / `token` lookups, register/unregister lifecycle. |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart` | **Create.** Extracted HTTP + SSE handling from `TeammateBusMcpServer` (per-handler instance, cancellable streams keyed by session). |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` | **Create.** Single HTTP + raw-socket listeners; route by `X-Session` or `X-Bus-Token`. |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_config.dart` | **Modify.** Add `X-Session` header; gateway URL helpers. |
| `client/lib/services/team_bus/mcp/teammate_bus_mcp_server.dart` | **Modify then delete.** Keep temporarily as thin wrapper delegating to gateway in tests, then remove. |
| `client/lib/cubits/chat/tab_team_bus_coordinator.dart` | **Modify.** `gateway.register` / `unregister` instead of `server.start()`. |
| `client/lib/cubits/chat/model/chat_tab.dart` | **Modify.** Remove `mcpServer`; keep `teamBus` + optional `busHandler` / session token. |
| `client/lib/cubits/chat/session_launch_service.dart` | **Modify.** Use `gateway.endpoint` + `X-Session` in MCP config. |
| `client/lib/app/app_shell.dart` | **Modify.** Construct + `await gateway.ensureStarted()` before `ChatCubit`. |
| `client/lib/cubits/chat_cubit.dart` | **Modify.** Inject gateway into coordinator; update `teammateBusMcpEndpointForSession`. |
| `client/lib/services/team_bus/member_bus_idle_endpoint.dart` | **Modify.** `MemberBusIdleEndpoint.local(gateway, sessionId)`. |
| `client/lib/services/team_bus/remote/remote_bus_mount.dart` | **Modify.** Tunnel to gateway ports; drop per-mount `BusHttpTokenGuard` / `BusRawSocketServer`. |
| `client/lib/services/team_bus/remote/ssh_remote_bus_mount_factory.dart` | **Modify.** Pass gateway instead of `TeammateBusMcpServer`. |
| `client/lib/services/team_bus/remote/member_bus_mcp_config.dart` | **Modify.** Local configs include `X-Session`; remote HTTP includes token only. |
| `client/lib/services/team_bus/remote/bus_http_token_guard.dart` | **Delete** after gateway inlines token check. |
| `tools/teammate_bus_bridge/bin/teammate_bus_bridge.dart` | **Modify.** `--session` + `X-Session` header on forward. |
| Tests (see tasks) | Migrate from per-server fixtures to gateway fixtures. |

---

## Routing contract (lock before coding)

### Local members (loopback HTTP / stdio bridge)

```
POST http://127.0.0.1:<gatewayPort>/mcp
Headers:
  X-Session: <appSessionId>
  X-Member:  <rosterMemberId>
```

```
POST http://127.0.0.1:<gatewayPort>/idle
Headers: same
```

### Remote members (HTTP — cursor)

```
POST http://127.0.0.1:<remoteTunnelPort>/mcp   # tunnels to gatewayPort
Headers:
  X-Bus-Token: <per-session token>
  X-Member:    <rosterMemberId>
```

Gateway resolves `token → sessionId` then dispatches to that session's handler. **No per-mount `BusHttpTokenGuard`.**

### Remote members (raw socket — long-blocking CLI)

Handshake line (unchanged shape, token scoped per session):

```json
{"token":"<per-session-token>","memberId":"<rosterMemberId>"}
```

All remote relays tunnel to **one** gateway raw-socket port; gateway maps `token → sessionId`.

### Registration API

```dart
class TeammateBusSessionRegistration {
  final String sessionId;
  final TeammateBusMcpHandler handler;
  final String token; // generated on register, revoked on unregister
}

abstract interface class TeammateBusMcpGateway {
  Future<void> ensureStarted();
  Uri get mcpEndpoint;   // http://127.0.0.1:<port>/mcp
  Uri get idleEndpoint;  // http://127.0.0.1:<port>/idle
  int get rawSocketPort;

  bool isSessionRegistered(String sessionId);

  TeammateBusSessionRegistration register({
    required String sessionId,
    required TeammateBusMcpHandler handler,
  });

  Future<void> unregister(String sessionId); // cancels only that session's SSE waits
}
```

---

### Task 1: Session registry

**Files:**
- Create: `client/lib/services/team_bus/mcp/teammate_bus_session_registry.dart`
- Test: `client/test/services/team_bus/mcp/teammate_bus_session_registry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_session_registry.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

void main() {
  test('register returns token and resolves handler by sessionId and token', () {
    final registry = TeammateBusSessionRegistry();
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final handler = TeammateBusMcpHandler(bus: bus);

    final reg = registry.register(sessionId: 'sess-a', handler: handler);

    expect(registry.handlerForSession('sess-a'), same(handler));
    expect(registry.sessionForToken(reg.token), 'sess-a');
  });

  test('unregister removes session and invalidates token', () {
    final registry = TeammateBusSessionRegistry();
    final handler = TeammateBusMcpHandler(
      bus: TeamBus(launcher: FakeMemberLauncher()),
    );
    final reg = registry.register(sessionId: 'sess-a', handler: handler);

    registry.unregister('sess-a');

    expect(registry.handlerForSession('sess-a'), isNull);
    expect(registry.sessionForToken(reg.token), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_session_registry_test.dart`
Expected: FAIL — `TeammateBusSessionRegistry` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
import 'dart:math';

import 'teammate_bus_mcp_handler.dart';

class TeammateBusSessionRegistration {
  TeammateBusSessionRegistration({
    required this.sessionId,
    required this.handler,
    required this.token,
  });

  final String sessionId;
  final TeammateBusMcpHandler handler;
  final String token;
}

class TeammateBusSessionRegistry {
  final _bySession = <String, TeammateBusSessionRegistration>{};
  final _tokenToSession = <String, String>{};

  TeammateBusSessionRegistration register({
    required String sessionId,
    required TeammateBusMcpHandler handler,
  }) {
    unregister(sessionId);
    final token = _randomToken();
    final reg = TeammateBusSessionRegistration(
      sessionId: sessionId,
      handler: handler,
      token: token,
    );
    _bySession[sessionId] = reg;
    _tokenToSession[token] = sessionId;
    return reg;
  }

  void unregister(String sessionId) {
    final existing = _bySession.remove(sessionId);
    if (existing != null) {
      _tokenToSession.remove(existing.token);
    }
  }

  TeammateBusMcpHandler? handlerForSession(String sessionId) =>
      _bySession[sessionId]?.handler;

  String? sessionForToken(String token) => _tokenToSession[token];

  TeammateBusSessionRegistration? registrationForSession(String sessionId) =>
      _bySession[sessionId];

  Iterable<TeammateBusSessionRegistration> get registrations =>
      _bySession.values;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_session_registry_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/mcp/teammate_bus_session_registry.dart \
        client/test/services/team_bus/mcp/teammate_bus_session_registry_test.dart
git commit -m "feat: add teammate-bus session registry for MCP gateway routing"
```

---

### Task 2: HTTP delegate (extract SSE logic)

**Files:**
- Create: `client/lib/services/team_bus/mcp/teammate_bus_mcp_http_delegate.dart`
- Test: `client/test/services/team_bus/mcp/teammate_bus_mcp_http_delegate_test.dart`
- Reference: `client/lib/services/team_bus/mcp/teammate_bus_mcp_server.dart` (copy `_streamLongRunning`, `_onRequest` body)

- [ ] **Step 1: Write the failing test** — copy `initialize over real HTTP` and `wait_for_message SSE` cases from `teammate_bus_mcp_server_test.dart`, but instantiate `TeammateBusMcpHttpDelegate(handler: ...)` and call `delegate.handlePost(mcpUri, headers, body)` returning a test response sink (or bind a temporary `HttpServer` that forwards to delegate).

Minimal approach: test via a tiny loopback server wrapper in the test file:

```dart
test('delegate routes initialize for member', () async {
  final bus = TeamBus(launcher: FakeMemberLauncher());
  final handler = TeammateBusMcpHandler(bus: bus);
  final delegate = TeammateBusMcpHttpDelegate(handler: handler);
  final res = await delegate.handleMcpPost(
    memberId: 'lead',
    body: jsonEncode({'jsonrpc': '2.0', 'id': 0, 'method': 'initialize'}),
  );
  expect(res.statusCode, HttpStatus.ok);
  // parse JSON body...
});
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement `TeammateBusMcpHttpDelegate`**

Move from `TeammateBusMcpServer`:
- `handleMcpPost({required String memberId, required String body})` → returns structured result or writes to `HttpResponse`
- `handleIdlePost({required String memberId})` → `String` body
- `streamLongRunning(...)` + `_activeStreams` per delegate instance
- `cancelAllStreams()` called on session unregister

Keep `progressInterval` constructor param (default 20s).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_mcp_http_delegate_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: extract teammate-bus HTTP/SSE delegate from per-session server"
```

---

### Task 3: MCP gateway (HTTP routing)

**Files:**
- Create: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_config.dart`
- Test: `client/test/services/team_bus/mcp/teammate_bus_mcp_gateway_test.dart`

- [ ] **Step 1: Add config constants**

In `teammate_bus_mcp_config.dart`:

```dart
/// Identifies the mixed session for gateway routing (local members).
const teammateBusMcpSessionHeader = 'X-Session';

Map<String, Object?> teammateBusMcpServerConfig({
  required Uri endpoint,
  required String sessionId,
  required String memberId,
}) {
  return {
    'type': 'http',
    'url': endpoint.toString(),
    'headers': {
      teammateBusMcpSessionHeader: sessionId,
      teammateBusMcpMemberHeader: memberId,
    },
  };
}
```

Update `teammateBusMcpServerConfigStdio` args to include `--session`.

- [ ] **Step 2: Write failing gateway tests**

Port these scenarios from `teammate_bus_mcp_server_test.dart`:

1. Two sessions registered → same gateway port → `X-Session` routes to correct handler (`send_message` delivered to right inbox).
2. Missing `X-Session` and missing/invalid `X-Bus-Token` → 400.
3. Valid `X-Bus-Token` routes without `X-Session`.
4. `unregister(sessionA)` does not cancel session B's active wait stream.

```dart
late TeammateBusMcpGateway gateway;
late TeamBus busA, busB;
late TeammateBusSessionRegistration regA, regB;

setUp(() async {
  gateway = TeammateBusMcpGateway();
  await gateway.ensureStarted();
  busA = TeamBus(launcher: FakeMemberLauncher());
  busB = TeamBus(launcher: FakeMemberLauncher());
  regA = gateway.register(
    sessionId: 'sess-a',
    handler: TeammateBusMcpHandler(bus: busA),
  );
  regB = gateway.register(
    sessionId: 'sess-b',
    handler: TeammateBusMcpHandler(bus: busB),
  );
});
```

Helper `rpc(sessionId, member, body)` sets both headers.

- [ ] **Step 3: Run tests — expect FAIL**

- [ ] **Step 4: Implement `TeammateBusMcpGateway`**

```dart
class TeammateBusMcpGateway implements TeammateBusMcpGateway {
  TeammateBusMcpGateway({this.progressInterval = const Duration(seconds: 20)});

  final _registry = TeammateBusSessionRegistry();
  final _delegates = <String, TeammateBusMcpHttpDelegate>{};
  HttpServer? _http;
  // ...

  @override
  Future<void> ensureStarted() async {
    if (_http != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = server;
    server.listen(_onRequest);
  }

  @override
  TeammateBusSessionRegistration register({...}) {
    final reg = _registry.register(sessionId: sessionId, handler: handler);
    _delegates[sessionId] = TeammateBusMcpHttpDelegate(
      handler: handler,
      progressInterval: progressInterval,
    );
    return reg;
  }

  @override
  Future<void> unregister(String sessionId) async {
    await _delegates.remove(sessionId)?.cancelAllStreams();
    _registry.unregister(sessionId);
  }

  // _resolveSession(HttpRequest): X-Session OR X-Bus-Token → sessionId
}
```

- [ ] **Step 5: Run gateway tests — expect PASS**

Run: `cd client && flutter test test/services/team_bus/mcp/teammate_bus_mcp_gateway_test.dart`

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: add single-port teammate-bus MCP gateway with session routing"
```

---

### Task 4: Gateway raw-socket demux

**Files:**
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Modify: `client/lib/services/team_bus/remote/bus_raw_socket_server.dart` (optional: accept registry callback instead of single handler)
- Test: `client/test/services/team_bus/mcp/teammate_bus_mcp_gateway_raw_socket_test.dart`

- [ ] **Step 1: Write failing test** — register two sessions with different tokens; connect raw socket with token A; `tools/list` returns tools for session A only.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Start one `BusRawSocketServer` inside gateway** (or inline demux) where handshake `token` resolves via `_registry.sessionForToken`, then dispatch to that session's handler.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: multiplex teammate-bus raw-socket relay on gateway port"
```

---

### Task 5: Wire app bootstrap + coordinator

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/cubits/chat/tab_team_bus_coordinator.dart`
- Modify: `client/lib/cubits/chat/model/chat_tab.dart`
- Test: `client/test/cubits/chat_cubit_team_bus_test.dart`

- [ ] **Step 1: Update failing `chat_cubit_team_bus_test`**

Change `_mcpEndpointAcceptsHttp` helper to send `X-Session: session.sessionId`.

Add explicit test:

```dart
test('two mixed sessions share the same gateway port', () async {
  // open session A and B ...
  final epA = cubit.teammateBusMcpEndpointForSession(sessA);
  final epB = cubit.teammateBusMcpEndpointForSession(sessB);
  expect(epA, isNotNull);
  expect(epA!.port, epB!.port);
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Bootstrap gateway in `app_shell.dart`**

Before `chatCubit = ChatCubit(...)`:

```dart
final teammateBusMcpGateway = TeammateBusMcpGateway();
await teammateBusMcpGateway.ensureStarted();
```

Pass `teammateBusMcpGateway` into `ChatCubit` constructor (new optional param, required in production shell).

- [ ] **Step 4: Update `TabTeamBusCoordinator`**

Constructor: `required TeammateBusMcpGateway gateway`.

`installBusForTab`:

```dart
await _gateway.ensureStarted(); // replaces per-tab server.start()
final handler = TeammateBusMcpHandler(...);
final reg = _gateway.register(sessionId: session.sessionId, handler: handler);
tab.teamBus = bus;
tab.busSessionRegistration = reg; // store token for remote mount
```

Remove `TeammateBusMcpServer` creation and `server.start()`.

Update `hasTeamBusResources`:

```dart
return tab?.teamBus != null && _gateway.isSessionRegistered(sessionId);
```

`teammateBusMcpEndpointForSession`:

```dart
if (!_gateway.isSessionRegistered(sessionId)) return null;
return _gateway.mcpEndpoint;
```

- [ ] **Step 5: Update teardown (coordinator owns unregister)**

`ChatTab.disposeBus` must **not** call gateway directly (tab has no gateway ref). Instead, `ChatCubit._tearDownTab` or `TabTeamBusCoordinator.disposeSessionBus(sessionId)`:

```dart
await _gateway.unregister(tab.info.id);
await tab.disposeBus(); // teamBus.dispose() only; no mcpServer
```

Remove `mcpServer?.stop()` from `ChatTab.disposeBus`.

- [ ] **Step 6: Run tests — PASS**

Run: `cd client && flutter test test/cubits/chat_cubit_team_bus_test.dart`

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: register mixed sessions with shared teammate-bus MCP gateway"
```

---

### Task 6: Session launch + MCP config + idle endpoint

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/services/team_bus/remote/member_bus_mcp_config.dart`
- Modify: `client/lib/services/team_bus/member_bus_idle_endpoint.dart`
- Test: `client/test/services/team_bus/member_remote_mcp_config_test.dart`
- Test: `client/test/services/cli/config_profile/opencode_idle_plugin_test.dart`

- [ ] **Step 1: Update tests** — local MCP config includes `X-Session`; endpoint URL no longer embeds session (same gateway URL for all).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Replace `tab.mcpServer` guards and endpoints**

Add to `SessionLaunchHost`:

```dart
TeammateBusMcpGateway get teammateBusMcpGateway;
```

Replace `mixedBus` predicate (~line 1489):

```dart
// before: tab.mcpServer != null
final mixedBus = team?.teamMode == TeamMode.mixed &&
    tab.teamBus != null &&
    _h.teammateBusMcpGateway.isSessionRegistered(activeSession.sessionId);
```

Replace `buildRemoteBusMount(busServer: tab.mcpServer!)` with gateway + session token:

```dart
buildRemoteBusMount(
  gateway: _h.teammateBusMcpGateway,
  sessionToken: tab.busSessionRegistration!.token,
  ...
)
```

In `_connectShell` / `extraMcpServers`:

```dart
teammateBusMcpServerName: buildMemberBusMcpConfig(
  memberId: launchMember.id,
  sessionId: activeSession.sessionId,
  gatewayEndpoint: _h.teammateBusMcpGateway.mcpEndpoint,
  ...
),
```

Update `buildMemberBusMcpConfig` signature to require `sessionId` for local paths.

`MemberBusIdleEndpoint.local`:

```dart
factory MemberBusIdleEndpoint.local(
  TeammateBusMcpGateway gateway,
  String sessionId,
) => MemberBusIdleEndpoint(
  url: gateway.idleEndpoint.toString(),
  sessionId: sessionId, // new field for headersFor
);
```

Extend `headersFor` to add `teammateBusMcpSessionHeader` when `sessionId` set.

- [ ] **Step 4: Run affected tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: point member MCP and idle plugins at shared gateway endpoint"
```

---

### Task 7: Remote bus mount simplification

**Files:**
- Modify: `client/lib/services/team_bus/remote/remote_bus_mount.dart`
- Modify: `client/lib/services/team_bus/remote/ssh_remote_bus_mount_factory.dart`
- Delete: `client/lib/services/team_bus/remote/bus_http_token_guard.dart`
- Test: `client/test/services/team_bus/member_remote_bus_loopback_test.dart`
- Test: `client/test/services/team_bus/remote_bus_binding_resolver_test.dart`

- [ ] **Step 1: Update tests** — `buildRemoteBusMount` takes `TeammateBusMcpGateway` + `sessionToken` instead of `TeammateBusMcpServer`.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Simplify `RemoteBusMount`**

Remove `_httpGuard` and per-mount `_rawSocket`. Tunnel directly to:

- `gateway.mcpEndpoint.port` for HTTP (cursor MCP + idle)
- `gateway.rawSocketPort` for long-blocking relay

Pass `token` from `TeammateBusSessionRegistration.token` (registered when session opens).

- [ ] **Step 4: Delete `bus_http_token_guard.dart`** and remove imports.

- [ ] **Step 5: Run remote bus tests — PASS**

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor: remote bus mounts tunnel to shared MCP gateway"
```

---

### Task 8: stdio bridge `--session`

**Files:**
- Modify: `tools/teammate_bus_bridge/bin/teammate_bus_bridge.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_config.dart`
- Modify: `tools/teammate_bus_bridge/tool/smoke.dart` (if present)
- Test: `client/test/services/team_bus/mcp/bus_bridge_locator_test.dart` (add header test via bridge smoke or unit test bridge arg parsing)

- [ ] **Step 1: Write failing test for `_parseArgs` including `--session`**

- [ ] **Step 2: Implement**

```dart
const _sessionHeader = 'X-Session';

// args: --session <id>
// forward: req.headers.set(_sessionHeader, session);
```

Update `teammateBusMcpServerConfigStdio`:

```dart
'args': <String>[
  '--member', memberId,
  '--session', sessionId,
  '--bus-url', endpoint.toString(),
],
```

- [ ] **Step 3: Run bridge smoke / tests — PASS**

Run: `cd tools/teammate_bus_bridge && dart run tool/smoke.dart` (update smoke to pass `--session`).

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: teammate_bus_bridge forwards X-Session to MCP gateway"
```

---

### Task 9: Remove legacy per-session server + test migration

**Files:**
- Delete: `client/lib/services/team_bus/mcp/teammate_bus_mcp_server.dart`
- Delete: `client/test/services/team_bus/mcp/teammate_bus_mcp_server_test.dart` (cases migrated to gateway/delegate tests)
- Modify: all integration harnesses listing `TeammateBusMcpServer`

Search:

```bash
cd client && rg -l 'TeammateBusMcpServer' lib test
```

Update:

- `client/test/integration/support/team_bus_comm_task_harness.dart`
- `client/test/integration/support/mixed_team_integration_harness.dart`
- `client/test/integration/support/teammate_bus_http_client.dart` — add required `sessionId` param; set `X-Session` on all POSTs
- `client/test/integration/support/teammate_bus_http_client_test.dart`
- `client/test/integration/support/session_idle_busy_harness.dart` — `postMemberIdle` sends `X-Session`
- `client/test/integration/support/bus_roster_assertions.dart` — replace `mcpServer?.activeWaitStreamCount` with `gateway.activeWaitStreamCountFor(sessionId)` (add gateway API)
- `client/test/integration/mixed_team_bus_ping_pong_integration_test.dart`
- `client/test/cubits/chat/chat_tab_remote_plane_test.dart` — new `RemoteBusMount` constructor
- Delete/migrate: `client/test/services/team_bus/bus_http_token_guard_test.dart` (guard removed; cover token routing in gateway tests)

Pattern:

```dart
final gateway = TeammateBusMcpGateway();
await gateway.ensureStarted();
gateway.register(sessionId: 'test', handler: TeammateBusMcpHandler(bus: bus));
```

- [ ] **Step 1: Migrate tests**

- [ ] **Step 2: Delete legacy server file**

- [ ] **Step 3: Full verify**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: zero analyze issues; all unit tests pass.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove per-session TeammateBusMcpServer after gateway migration"
```

---

### Task 10: Docs + AGENTS.md touch-up

**Files:**
- Modify: `AGENTS.md` (TeamBus section — single gateway port)
- Modify: `docs/remote-execution-architecture.md` (replace per-session port references)
- Create: `docs/superpowers/specs/2026-07-02-teammate-bus-mcp-gateway-design.md` (short design recap)

- [ ] **Step 1: Write spec doc** (1–2 pages: routing headers, lifecycle, remote tunnel).

- [ ] **Step 2: Update AGENTS.md** — `TeammateBusMcpGateway` @ loopback single port; mixed session registers handler.

- [ ] **Step 3: Commit**

```bash
git commit -m "docs: teammate-bus MCP gateway architecture"
```

---

## Manual golden path (post-implementation)

1. Open a mixed team session with 2+ members (local).
2. Confirm both members' generated MCP config points to the **same** `url` and different `X-Session` is N/A per member file — same session id in headers.
3. Open a **second** mixed session; verify `lsof -iTCP -sTCP:LISTEN | grep teampilot` shows **one** loopback HTTP listener for bus (not two).
4. Ping-pong message between members in session A; confirm session B inboxes untouched.
5. (If SSH available) Remote long-blocking member: relay connects; `wait_for_message` blocks; token from session registration works.

---

## Out of scope (YAGNI)

- Well-known fixed port number (e.g. always `17352`) — still bind `0` once; port stable for process lifetime.
- Cross-session message bus or shared task queue.
- Migrating non-mixed (native) Claude swarm to gateway.
- CI integration test for SSH remote (keep existing tags).

---

## Risk notes

| Risk | Mitigation |
|------|------------|
| Stale CLI configs cache old per-session port | Session connect always regenerates MCP config from `gateway.mcpEndpoint`. |
| Forgot `X-Session` on local calls | Gateway returns 400 with explicit log; tests enforce header. |
| `unregister` cancels wrong waits | Per-session delegate owns `_activeStreams`; test Task 3 case 4. |
| Bridge binary not rebuilt | Document `dart compile exe` in `tools/teammate_bus_bridge/README.md`; CI optional smoke. |
