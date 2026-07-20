# Agent Permission Attention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface Orca-style “needs you” attention when a seat pauses on a CLI permission prompt, so History/sidebar users can jump to Terminal without guessing.

**Architecture:** Session provision installs managed status hooks/plugins that POST to `POST /agent-status` on the **existing** `TeammateBusMcpGateway` loopback HTTP server (same port as `/idle` and `/mcp` — separate route + handler, not a second bind). Pure normalizers map CLI payloads → `working|waiting|done`. `AgentAttentionCubit` holds seat-keyed state (skip-permissions gated, 30m stale TTL). History banner + sidebar marker navigate via `setSessionWorkbenchView(terminal)` + `selectMember`. Cursor uses live OSC title observation + classifier only. TeamBus `/idle` semantics stay untouched. SSH: mixed seats reuse `RemoteBusMount` HTTP tunnel; simple/non-mixed SSH seats get an HTTP reverse tunnel to the same `httpBusPort`.

**Tech Stack:** Dart / Flutter (`flutter_bloc`, existing `TeammateBusMcpGateway` / `RemoteBusMount`, CLI config profiles, PTY `feedPtyBytes`); no new packages.

**Spec:** [`docs/superpowers/specs/2026-07-19-agent-permission-attention-design.md`](../specs/2026-07-19-agent-permission-attention-design.md)

**Orca references (copy rules, do not vendor):**
- `orca/src/shared/agent-hook-listener.ts` — normalize PermissionRequest / AskUserQuestion / Stop
- `orca/src/main/agent-hooks/server.ts` — sticky wait, 30m stale
- `orca/src/shared/terminal-title-status.ts` + `osc-title-extraction.ts` — Cursor title
- `orca/src/main/opencode/hook-service.ts` — `permission.asked` / `question.asked`

---

## Architecture lock (SSH + HTTP)

| Decision | Detail |
|----------|--------|
| Bind | **One** `HttpServer` — extend `TeammateBusMcpGateway._onRequest` with `POST /agent-status` |
| Semantics | Status handler → normalizer → `AgentAttentionCubit`; **never** calls `handleIdleRequest` / TeamBus park |
| Auth | Reuse `X-Session` / `X-Member` / `X-Bus-Token`. Status may resolve session **without** a TeamBus MCP `_delegates` entry (simple seats register status-only) |
| Local URL | `http://127.0.0.1:<gateway.port>/agent-status` |
| Mixed SSH | Reuse existing tunnel to `httpBusPort`; `RemoteBusBinding.agentStatusUrl` → `http://127.0.0.1:$idleHttpTunnelPort/agent-status` |
| Simple / non-mixed SSH | `RemoteBusMount.bindHttpMember` to same gateway port; register token; stamp remote `agentStatusUrl`. Soft-fail on tunnel error (launch continues, no attention) |
| WSL | Stamp local gateway URL (like non-SSH idle); no SSH reverse tunnel |
| Env | `TEAMPILOT_AGENT_STATUS_URL` = that URL |

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/lib/services/agent_status/agent_attention_state.dart` | `AgentSeatAttention` enum + seat key helpers |
| Create: `client/lib/services/agent_status/agent_status_event.dart` | Normalized event `{state, cli, toolName?}` |
| Create: `client/lib/services/agent_status/agent_status_normalizer.dart` | Per-`CliTool` raw JSON → event (pure) |
| Create: `client/test/services/agent_status/agent_status_normalizer_test.dart` | Fixture payloads |
| Create: `client/lib/cubits/agent_attention_cubit.dart` | Seat map, skip gate, TTL, clearSeat |
| Create: `client/test/cubits/agent_attention_cubit_test.dart` | Multi-seat + skip + TTL + clear |
| Create: `client/lib/services/agent_status/member_agent_status_endpoint.dart` | Local/remote URL + `headersFor` |
| Create: `client/lib/services/agent_status/agent_status_http_handler.dart` | Parse body → normalize → cubit |
| Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart` | Route `POST /agent-status`; status-only session register |
| Create: `client/test/services/agent_status/agent_status_gateway_route_test.dart` | Auth + route → cubit (via real gateway) |
| Create: `client/lib/services/cli/registry/config_profile/agent_status_hooks.dart` | Claude-family HTTP hook merge |
| Modify: Claude + flashskyai config profile capabilities | Install status hooks for simple+team |
| Modify: `client/lib/services/provider/codex/codex_team_bus_overlay.dart` (+ capability) | PermissionRequest → `/agent-status` |
| Create: OpenCode status plugin next to `opencode_idle_plugin.dart` | `permission.asked` / clear events |
| Modify: `config_profile_context.dart`, lifecycle/shell connector | Stamp `agentStatus` + env always; SSH tunnel for non-mixed |
| Modify: `member_bus_mcp_config.dart` | `agentStatusUrl` getter |
| Modify: `app_shell.dart`, `main.dart` | Wire cubit + handler into gateway; BlocProvider |
| Create: `client/lib/pages/chat/agent_permission_attention_banner.dart` | History top strip + jump CTA |
| Modify: History review / workbench | Show banner when selected seat waiting |
| Modify: `sidebar_session_tile.dart` (+ tests) | Needs-you marker ≠ working spinner |
| Create: `osc_title_extractor.dart` + `cursor_title_attention.dart` | OSC parse + classifier |
| Modify: `terminal_launch_controller.dart` | Cursor-only title tap on `feedPtyBytes` |
| Modify: `app_en.arb` / `app_zh.arb` | Banner strings |
| Modify: dispose/disconnect paths | `clearSeat` on PTY dispose |

**Out of scope:** in-chat Allow; OSC title **write**; Copilot `blocked`; Cursor shell-before → waiting; changing `/idle` park semantics.

---

### Task 1: Attention types + normalizer (pure)

**Files:**
- Create: `client/lib/services/agent_status/agent_attention_state.dart`
- Create: `client/lib/services/agent_status/agent_status_event.dart`
- Create: `client/lib/services/agent_status/agent_status_normalizer.dart`
- Create: `client/test/services/agent_status/agent_status_normalizer_test.dart`

- [ ] **Step 1: Write failing normalizer tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_status_normalizer.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';

void main() {
  group('AgentStatusNormalizer', () {
    test('Claude PermissionRequest → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PermissionRequest', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude AskUserQuestion PreToolUse → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {
          'hook_event_name': 'PreToolUse',
          'tool_name': 'AskUserQuestion',
        },
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Claude Stop → done', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'Stop'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('Claude UserPromptSubmit → working', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'UserPromptSubmit'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('Claude PostToolUse → working (clears wait)', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.claude,
        body: {'hook_event_name': 'PostToolUse', 'tool_name': 'Bash'},
      );
      expect(e?.state, AgentSeatAttention.working);
    });

    test('flashskyai uses Claude-family rules', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.flashskyai,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('Codex PermissionRequest → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.codex,
        body: {'hook_event_name': 'PermissionRequest'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode permission.asked → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'permission.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode question.asked → waiting', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'question.asked'},
      );
      expect(e?.state, AgentSeatAttention.waiting);
    });

    test('OpenCode session.idle → done', () {
      final e = AgentStatusNormalizer.normalize(
        cli: CliTool.opencode,
        body: {'event': 'session.idle'},
      );
      expect(e?.state, AgentSeatAttention.done);
    });

    test('corrupt / unknown → null', () {
      expect(
        AgentStatusNormalizer.normalize(cli: CliTool.claude, body: {}),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart
```

Expected: missing library / type.

- [ ] **Step 3: Implement types + normalizer**

```dart
enum AgentSeatAttention { working, waiting, done }

String agentSeatKey({required String sessionId, required String memberId}) =>
    '${sessionId.trim()}\u0000${memberId.trim()}';
```

Normalizer: switch on `CliTool`; Claude/Codex/flashskyai use `hook_event_name`; OpenCode uses `event`. v1 sticky: PostToolUse / Stop / UserPromptSubmit clear wait. Cursor: always return null (title path only).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/agent_status/agent_status_normalizer_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/ client/test/services/agent_status/agent_status_normalizer_test.dart
git commit -m "$(cat <<'EOF'
feat(agent-status): add attention states and per-CLI normalizer

Map PermissionRequest / OpenCode asked events to waiting without UI yet.
EOF
)"
```

---

### Task 2: AgentAttentionCubit

**Files:**
- Create: `client/lib/cubits/agent_attention_cubit.dart`
- Create: `client/test/cubits/agent_attention_cubit_test.dart`

- [ ] **Step 1: Write failing cubit tests**

Include: waiting + `sessionHasWaiting`; skipPermissions suppresses waiting; `clearSeat`; `done` clears waiting; multi-seat `waitingMemberIds`; **stale TTL** (inject `DateTime Function() now` or advance clock so entry older than 30m is dropped on read/apply).

```dart
test('stale entries older than 30m are dropped', () {
  var now = DateTime.utc(2026, 7, 19, 12);
  final c = AgentAttentionCubit(clock: () => now);
  c.applyEvent(
    sessionId: 's1',
    memberId: 'm1',
    event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
    skipPermissions: false,
  );
  now = now.add(const Duration(minutes: 31));
  expect(c.state.sessionHasWaiting('s1'), isFalse);
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/cubits/agent_attention_cubit_test.dart
```

- [ ] **Step 3: Implement cubit**

State: `Map` seatKey → `{attention, updatedAt}`. Constant `agentAttentionStaleAfter = Duration(minutes: 30)`. Prune on apply/read.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test test/cubits/agent_attention_cubit_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/agent_attention_cubit.dart client/test/cubits/agent_attention_cubit_test.dart
git commit -m "$(cat <<'EOF'
feat(agent-status): add AgentAttentionCubit with skip and stale TTL

Seat-keyed waiting state for History/sidebar consumers.
EOF
)"
```

---

### Task 3: `/agent-status` on TeammateBusMcpGateway

**Files:**
- Create: `client/lib/services/agent_status/member_agent_status_endpoint.dart`
- Create: `client/lib/services/agent_status/agent_status_http_handler.dart`
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart`
- Create: `client/test/services/agent_status/agent_status_gateway_route_test.dart`

**Do not** create a second `HttpServer`.

- [ ] **Step 1: Write failing gateway route tests**

```dart
test('POST /agent-status with X-Session + X-Member applies waiting', () async {
  final cubit = AgentAttentionCubit();
  final gw = TeammateBusMcpGateway();
  await gw.ensureStarted();
  gw.attachAgentStatusHandler(AgentStatusHttpHandler(
    attention: cubit,
    resolveCli: (_, __) => CliTool.claude,
    resolveSkipPermissions: (_, __) => false,
  ));
  gw.registerAgentStatusSession(sessionId: 's1'); // status-only, no TeamBus handler
  final uri = Uri.parse('http://127.0.0.1:${gw.httpPort}/agent-status');
  // POST JSON PermissionRequest with X-Session=s1, X-Member=m1
  expect(cubit.state.sessionHasWaiting('s1'), isTrue);
  await gw.dispose(); // or existing shutdown if any
});

test('missing X-Member → 400', () async { /* … */ });
test('unknown session → 400', () async { /* … */ });
test('POST /idle still uses TeamBus idle path (unchanged)', () async {
  // smoke: registered TeamBus session idle still works if existing test covers it;
  // at minimum assert /agent-status does not call notifyIdle
});
```

Expose `httpPort` getter if missing (or parse from `idleEndpoint.port`).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/agent_status/agent_status_gateway_route_test.dart
```

- [ ] **Step 3: Implement handler + gateway route**

In `_onRequest`, **before** requiring `_delegates[sessionId]`:

```dart
if (request.method == 'POST' && request.uri.path == '/agent-status') {
  final sessionId = _resolveSessionId(request);
  if (sessionId == null || !_agentStatusSessions.contains(sessionId)) {
    // also allow sessions that have TeamBus registration
    …
  }
  await _agentStatusHandler!.handle(request, sessionId: sessionId, memberId: member);
  return;
}
```

`registerAgentStatusSession` / `unregisterAgentStatusSession` + token map reuse `_registry` token APIs where possible so remote `X-Bus-Token` resolves.

`MemberAgentStatusEndpoint.local(gateway, sessionId:)` → `idleEndpoint` host/port with path `/agent-status`.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test test/services/agent_status/agent_status_gateway_route_test.dart \
  test/services/team_bus/mcp/teammate_bus_mcp_gateway_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/agent_status/ \
  client/lib/services/team_bus/mcp/teammate_bus_mcp_gateway.dart \
  client/test/services/agent_status/agent_status_gateway_route_test.dart
git commit -m "$(cat <<'EOF'
feat(agent-status): route /agent-status on TeamBus HTTP gateway

Same port as /idle so SSH tunnels deliver permission hooks.
EOF
)"
```

---

### Task 4: DI — cubit + handler into gateway

**Files:**
- Modify: `client/lib/app/app_shell.dart` (near `TeammateBusMcpGateway` construction)
- Modify: `client/lib/main.dart` (`MultiBlocProvider`)

- [ ] **Step 1: Wire construction**

1. Create `AgentAttentionCubit`
2. `gateway.attachAgentStatusHandler(...)` with `resolveCli` / `resolveSkipPermissions` callbacks (thin `AgentStatusSeatLookup`; **both** lookups completed in Task 7 — Task 4 may use temporary fixed lambdas only in unit tests, not ship a Claude-only stub in production DI)
3. `BlocProvider.value(value: agentAttentionCubit)` in `main.dart`

No second `ensureStarted` — gateway already started for TeamBus.

- [ ] **Step 2: Smoke analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "$(cat <<'EOF'
feat(agent-status): attach status handler and provide attention cubit

Boot wires /agent-status into the existing TeamBus gateway.
EOF
)"
```

---

### Task 5: Claude + flashskyai status hook install

**Files:**
- Create: `client/lib/services/cli/registry/config_profile/agent_status_hooks.dart`
- Create: `client/test/services/cli/config_profile/agent_status_hooks_test.dart`
- Modify: `claude_config_profile_capability.dart`, `flashskyai_config_profile_capability.dart`
- Modify: `config_profile_context.dart` — add `MemberAgentStatusEndpoint? agentStatus`

- [ ] **Step 1: Failing merge test** (mirror `claude_stop_idle_hook_test.dart`)

Assert `PermissionRequest` (+ Pre/Post/Stop/UserPromptSubmit) HTTP hooks; idempotent for same URL.

- [ ] **Step 2: Implement `mergeAgentStatusHooks`**

Same HTTP hook shape as `mergeStopIdleHook`; headers via `endpoint.headersFor(memberId)`.

- [ ] **Step 3: Call from Claude + flashskyai writers**

Install when `agentStatus != null` for **simple and team** — **not** gated on `mixed`.

- [ ] **Step 4: Tests PASS**

```bash
cd client && flutter test test/services/cli/config_profile/agent_status_hooks_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): install Claude-family permission attention hooks

Simple and team seats POST PermissionRequest to /agent-status.
EOF
)"
```

---

### Task 6: Codex + OpenCode status provision

**Files:**
- Modify: `client/lib/services/provider/codex/codex_team_bus_overlay.dart` (path under `services/provider/codex/`, not `cli/registry/provider/`)
- Modify: Codex config profile capability
- Create: `…/config_profile/opencode_agent_status_plugin.dart`
- Modify: `opencode_config_profile_capability.dart`
- Tests for both

- [ ] **Step 1: Codex failing test** — PermissionRequest curl/trust posts to `agentStatus.url`

- [ ] **Step 2: Implement Codex status hooks** when `agentStatus != null` (keep Stop→`/idle` mixed-only)

- [ ] **Step 3: OpenCode plugin** — `permission.asked` / `question.asked` → waiting; `session.idle` → done; env `TEAMPILOT_AGENT_STATUS_URL` + member/session/token headers. Install whenever `agentStatus != null`.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): provision Codex hooks and OpenCode status plugin

Permission asked events reach /agent-status for both CLIs.
EOF
)"
```

---

### Task 7: Lifecycle stamp + SSH tunnel for every seat + skip lookup

**Files:**
- Modify: `session_shell_connector.dart`, `session_connect_orchestrator.dart`, `member_lifecycle_connect_gate.dart`
- Modify: `session_lifecycle_service.dart` / `config_profile_service.dart` — thread `agentStatus`
- Modify: `member_bus_mcp_config.dart` — `String get agentStatusUrl => 'http://127.0.0.1:$idleHttpTunnelPort/agent-status';`
- Modify: shell connector — call existing `RemoteBusMount.bindHttpMember` for simple/non-mixed SSH status tunnel
- Register/unregister agent-status session on connect/dispose
- Wire **both** `resolveCli` and `resolveSkipPermissions` on `AgentStatusSeatLookup`

**Seat key:** team = roster member **instance** id (TeamBus `X-Member` / replica id); simple = `session.sessionId`.

- [ ] **Step 1: Always build endpoint**

```dart
// Local (including RuntimeKind.wsl — stamp local gateway URL; no SSH reverse tunnel):
MemberAgentStatusEndpoint.local(gateway, sessionId: session.sessionId);

// Mixed SSH (existing remoteBinding):
MemberAgentStatusEndpoint.remote(binding); // uses binding.agentStatusUrl

// Simple or non-mixed SSH:
// Use RemoteBusMount.bindHttpMember (existing) targeting gateway httpBusPort.
// Register token on gateway. Stamp remote endpoint.
// NEVER stamp app-host 127.0.0.1 for a remote agent process.
//
// Soft-fail (spec): if tunnel open/bind throws or returns unavailable,
// log warning, set agentStatus=null for that seat, and CONTINUE launch.
// Do NOT copy _bindMixedRemoteBus hard-fail behavior for status-only tunnels.
```

Unlike `busIdle`, do **not** null out for non-mixed when tunnel succeeds.

- [ ] **Step 2: Register status session on connect; clear on disconnect**

`gateway.registerAgentStatusSession(sessionId: …, token: …?)`  
PTY dispose → `attention.clearSeat`  
Tab close → `clearSession` + unregister

- [ ] **Step 3: Complete seat lookups** (from Task 4 stubs)

- `resolveSkipPermissions(sessionId, memberId)` — same source as launch/continue `dangerouslySkipPermissions`.
- `resolveCli(sessionId, memberId)` — **required**: same connect-time seat CLI used for launch (`memberLaunchCli` / simple session CLI). OpenCode POSTs use `event` not `hook_event_name`; a Claude-only stub would drop OpenCode waiting. Prefer a small in-memory seat map updated at connect (`registerSeat(sessionId, memberId, cli, skip)`) cleared on disconnect over fragile cross-cubit reads.

- [ ] **Step 4: Focused test**

- `ConfigProfileLaunchContext.agentStatus` non-null for simple local fixture  
- Unit test: `RemoteBusBinding.agentStatusUrl` path ends with `/agent-status`  
- When `RuntimeKind.ssh` and not mixed, connector calls `bindHttpMember` (mock mount) before stamping URL  
- Soft-fail: mocked tunnel failure ⇒ launch path still returns success / continues; `agentStatus` null; warning logged  
- Seat lookup: registered OpenCode seat ⇒ `resolveCli` returns `CliTool.opencode`

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): stamp status URL for all seats including simple SSH

Reuse mixed idle tunnel; open HTTP tunnel for non-mixed remote seats.
EOF
)"
```

---

### Task 8: History banner + l10n + jump

**Files:**
- Modify: `app_en.arb`, `app_zh.arb`
- Create: `agent_permission_attention_banner.dart`
- Modify: History review messages (top strip like soft-reload)
- `AppKeys` + widget test

- [ ] **Step 1: ARB** — `agentPermissionAttentionBanner`, `agentPermissionOpenTerminal` (EN+ZH); gen-l10n / warmup glyphs if required

- [ ] **Step 2: Banner** when History view + selected seat `waiting`; CTA → `setSessionWorkbenchView(terminal)` (+ `selectMember` if needed). No auto-switch on waiting.

- [ ] **Step 3: Widget test**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): show History banner to jump to Terminal

Surfaces waiting permission attention without in-chat Allow UI.
EOF
)"
```

---

### Task 9: Sidebar needs-you marker + jump

**Files:**
- Modify: `sidebar_session_tile.dart`, working indicator sibling, sidebar builders
- Extend `sidebar_session_tile_test.dart`

- [x] **Step 1: Test** — waiting marker distinct from `workingSessionIds` spinner

- [x] **Step 2: Implement** distinct affordance; click → open session + Terminal + first waiting seat

- [x] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): mark sidebar sessions that need Terminal attention

Distinct from working spinner; click focuses waiting seat in Terminal.
EOF
)"
```

---

### Task 10: Cursor live OSC title attention

**Files:**
- Create: `client/lib/utils/terminal/osc_title_extractor.dart` + test
- Create: `client/lib/services/agent_status/cursor_title_attention.dart` + test
- Modify: `terminal_launch_controller.dart` (`feedPtyBytes`)
- Do **not** map Cursor shell-before hooks to waiting

- [x] **Step 1: OSC extractor tests** (BEL + ST terminators; cmds 0/1/2)

- [x] **Step 2: Classifier tests**

```dart
expect(detectCursorTitleAttention('Cursor Agent'), isNull);
expect(detectCursorTitleAttention('Cursor - action required'),
    AgentSeatAttention.waiting);
```

- [x] **Step 3: Tap feedPtyBytes** for Cursor seats only; pass the seat’s registered `skipPermissions` into `attention.applyEvent` (YOLO Cursor must not surface waiting from title matches); clear waiting when title no longer matches after prior waiting

- [x] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(agent-status): observe Cursor PTY titles for permission attention

Live OSC parse + classifier; bare Cursor Agent never marks waiting.
EOF
)"
```

---

### Task 11: Verification sweep

- [ ] **Step 1: Unit tests** for agent_status, cubit, hooks, sidebar, OSC

```bash
cd client && flutter test test/services/agent_status/ test/cubits/agent_attention_cubit_test.dart
```

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Optional** `@Tags(['integration'])` local PermissionRequest POST

- [ ] **Step 4: Commit fixes if any**

---

## Execution notes

- **TDD** each task; **DRY** reuse TeamBus port/headers/tunnels; **YAGNI** no in-chat Allow / OSC write / `blocked`.
- Claude sticky tool_use_id matching may stay simplified (clear on Stop/PostToolUse).
- Cursor without title changes may rarely wait — channel must still be live and tested with injected OSC bytes.
- Registry discipline: installers under config profiles / provider overlays; avoid UI `if (cli == …)`.
