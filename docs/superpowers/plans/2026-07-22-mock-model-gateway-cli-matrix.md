# Mock Model Gateway + CLI Message Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a pluggable mock model gateway and a CLI × mode matrix that drives History compose → deliver → chat bubbles (≥3 assistant replies + team collab), fixing real product bugs when cells go red.

**Architecture:** New `tools/mock_model_gateway` (ScenarioEngine + WireAdapters + HTTP server). Client integration harness `CliMessageMatrixHarness` + per-CLI `CliTestProfile` pumps `SessionChatView`, asserts gateway log + PTY markers + `AiHistoryCubit` bubbles. Replace `mock_anthropic` once Claude L2 cells run on the gateway.

**Tech Stack:** Dart (`tools/mock_model_gateway`), Flutter test / `linux-pty` integration tags, existing `ChatCubit` / `AiHistoryCubit` / TeamBus harness pieces.

**Spec:** `docs/superpowers/specs/2026-07-22-mock-model-gateway-cli-matrix-design.md`

---

## File map

| File | Role |
|------|------|
| `tools/mock_model_gateway/pubspec.yaml` | New package |
| `tools/mock_model_gateway/lib/core/turns.dart` | `TextTurn` / `ToolUseTurn` / `AssignedTaskUpdateTurn` (logical `toolRef`) |
| `tools/mock_model_gateway/lib/core/scenario_engine.dart` | Actor-keyed scenarios + request log |
| `tools/mock_model_gateway/lib/core/tool_name_resolver.dart` | `toolRef → on-wire name` callback interface |
| `tools/mock_model_gateway/lib/wire/wire_adapter.dart` | Adapter interface |
| `tools/mock_model_gateway/lib/wire/anthropic_messages_adapter.dart` | `/v1/messages` SSE (port from `mock_anthropic`) |
| `tools/mock_model_gateway/lib/wire/openai_chat_adapter.dart` | `/v1/chat/completions` |
| `tools/mock_model_gateway/lib/wire/openai_responses_adapter.dart` | `/v1/responses` (codex) |
| `tools/mock_model_gateway/lib/wire/cursor_adapter.dart` | Cursor redirect surface (after discovery spike) |
| `tools/mock_model_gateway/lib/server.dart` | Multi-path HTTP server |
| `tools/mock_model_gateway/lib/scenarios/*.dart` | `simple_3turn`, `native_collab_3plus`, `mixed_collab_3plus` |
| `tools/mock_model_gateway/bin/mock_model_gateway.dart` | Manual run entry |
| `tools/mock_model_gateway/test/*.dart` | L0 unit tests |
| `client/pubspec.yaml` | Depend on `mock_model_gateway`; drop `mock_anthropic` at end |
| `client/test/integration/support/cli_test_profile.dart` | Per-CLI profile |
| `client/test/integration/support/cli_message_matrix_harness.dart` | Matrix harness |
| `client/test/integration/support/chat_thread_assertions.dart` | Bubble / Queued assertions + thread dump |
| `client/test/integration/cli_message_matrix_*_test.dart` | L2 cells (or one parameterized file) |
| `client/test/integration/mock_model_gateway_l1_test.dart` | L1 HTTP (cross-platform) |
| `docs/DEVELOPMENT.md` | L0/L1/L2 commands |
| `tools/mock_anthropic/` | Delete after Claude migration |

**Product code:** touch only when a matrix cell attributes a product fault (History continue, mailbox Queued→sticky, PTY inject, live refresh, boot gates). Paths commonly involved: `client/lib/pages/chat/session_history_review_submit.dart`, `history_continue_delivery.dart`, `session_chat_view.dart`, `tab_member_pty_delivery.dart`, `AiHistoryCubit`.

---

## Standing rules (every L2 cell)

1. Prefer TDD: failing assertion first when adding a new cell.
2. On red: dump gateway log + PTY frame + thread dump; attribute per spec; **fix product if product**; re-run same cell.
3. Never skip except missing binary or N/A native.
4. Never lower ≥3 assistant bubbles or bypass History compose submit.

---

### Task 1: Scaffold `mock_model_gateway` + ScenarioEngine (L0)

**Files:**
- Create: `tools/mock_model_gateway/pubspec.yaml`
- Create: `tools/mock_model_gateway/analysis_options.yaml` (copy lints from `mock_anthropic`)
- Create: `tools/mock_model_gateway/lib/core/turns.dart`
- Create: `tools/mock_model_gateway/lib/core/scenario_engine.dart`
- Create: `tools/mock_model_gateway/lib/core/tool_name_resolver.dart`
- Create: `tools/mock_model_gateway/test/scenario_engine_test.dart`

- [ ] **Step 1: Create package skeleton**

`tools/mock_model_gateway/pubspec.yaml`:

```yaml
name: mock_model_gateway
description: Multi-protocol mock model gateway for TeamPilot CLI matrix tests
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.7.0

dev_dependencies:
  test: ^1.25.0
  lints: ^5.0.0
```

- [ ] **Step 2: Write failing ScenarioEngine tests**

```dart
import 'package:mock_model_gateway/core/scenario_engine.dart';
import 'package:mock_model_gateway/core/turns.dart';
import 'package:test/test.dart';

void main() {
  test('advances turns per actor and exhausts loudly', () {
    final engine = ScenarioEngine({
      'a': MockScenario(turns: [
        TextTurn('one'),
        TextTurn('two'),
        TextTurn('three'),
      ]),
    });
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(engine.nextTurn('a'), isA<TextTurn>());
    expect(() => engine.nextTurn('a'), throwsStateError);
  });

  test('resolves toolRef via ToolNameResolver', () {
    final engine = ScenarioEngine(
      {
        'a': MockScenario(turns: [
          ToolUseTurn(id: '1', toolRef: 'teambus.send_message', input: {'to': 'w'}),
        ]),
      },
      toolNames: (ref) => 'mcp__teammate-bus__$ref'.replaceAll('teambus.', ''),
    );
    final turn = engine.nextResolvedTurn('a');
    expect(turn, isA<ResolvedToolUseTurn>());
    expect((turn as ResolvedToolUseTurn).wireName, 'mcp__teammate-bus__send_message');
  });
}
```

Adjust API names to match your implementation, but keep: per-actor index, exhaust = `StateError`, logical `toolRef` resolution.

- [ ] **Step 3: Implement minimal engine + turns**

Implement `TextTurn`, `ToolUseTurn(toolRef,…)`, `AssignedTaskUpdateTurn`, `ScenarioEngine`, `ToolNameResolver` typedef / interface, `nextResolvedTurn` that maps `toolRef` → wire name before adapters encode.

- [ ] **Step 4: Run L0 tests**

```bash
cd tools/mock_model_gateway && dart test
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tools/mock_model_gateway
git commit -m "feat(mock-gateway): add ScenarioEngine and turn DSL"
```

---

### Task 2: Anthropic Messages WireAdapter (port)

**Files:**
- Create: `tools/mock_model_gateway/lib/wire/wire_adapter.dart`
- Create: `tools/mock_model_gateway/lib/wire/anthropic_messages_adapter.dart`
- Create: `tools/mock_model_gateway/lib/wire/anthropic_sse_encoder.dart` (port from `tools/mock_anthropic/lib/sse/anthropic_sse_encoder.dart`)
- Create: `tools/mock_model_gateway/test/anthropic_messages_adapter_test.dart`
- Port helpers: assigned-task resolution from `mock_anthropic` as needed

- [ ] **Step 1: Write failing encode/decode tests**

Assert: `TextTurn` → SSE with assistant text; `ResolvedToolUseTurn` → tool_use block; inbound JSON with tool_result feeds `AssignedTaskUpdateTurn` resolution.

- [ ] **Step 2: Run — expect FAIL**

```bash
cd tools/mock_model_gateway && dart test test/anthropic_messages_adapter_test.dart
```

- [ ] **Step 3: Port encoder + implement adapter**

Reuse `mock_anthropic` SSE shapes; paths: `/v1/messages`, `/anthropic/v1/messages`, `*/v1/messages`.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(mock-gateway): add Anthropic Messages wire adapter"
```

---

### Task 3: OpenAI Chat Completions WireAdapter

**Files:**
- Create: `tools/mock_model_gateway/lib/wire/openai_chat_adapter.dart`
- Create: `tools/mock_model_gateway/test/openai_chat_adapter_test.dart`

- [ ] **Step 1: Failing tests for `/v1/chat/completions`**

Cover streaming or non-streaming response shape that opencode / flashskyai openai mode accept. Prefer the simpler shape first; if a CLI requires stream, implement SSE `data:` chunks.

- [ ] **Step 2: Implement adapter → PASS → Commit**

```bash
git commit -m "feat(mock-gateway): add OpenAI Chat Completions wire adapter"
```

---

### Task 4: OpenAI Responses WireAdapter (codex)

**Files:**
- Create: `tools/mock_model_gateway/lib/wire/openai_responses_adapter.dart`
- Create: `tools/mock_model_gateway/test/openai_responses_adapter_test.dart`

- [ ] **Step 1: Spike codex request path against a dry run** (optional 15–30m)

Run codex once pointed at a dumping proxy or read codex config `wire_api = responses` docs/code in-repo. Record: path, auth header, minimal successful response body for one text turn + one tool call.

- [ ] **Step 2: Failing tests from recorded shape → implement → PASS → Commit**

```bash
git commit -m "feat(mock-gateway): add OpenAI Responses wire adapter"
```

---

### Task 5: Multi-protocol HTTP server + L1 integration test

**Files:**
- Create: `tools/mock_model_gateway/lib/server.dart`
- Create: `tools/mock_model_gateway/bin/mock_model_gateway.dart`
- Create: `tools/mock_model_gateway/test/server_l1_test.dart`
- Create: `client/test/integration/mock_model_gateway_l1_test.dart` (tag `integration` + `cross-platform`) **or** keep L1 inside the package — prefer package tests for L1, client file only if you need flutter_test. Spec allows `integration && cross-platform`; use package `dart test` for pure HTTP L1 and document it as L1.
- Modify: `client/pubspec.yaml` — add path dep on `mock_model_gateway`

- [ ] **Step 1: Implement `MockModelGatewayServer`**

Bind loopback:0; route by path to Anthropic / Chat / Responses adapters; unknown apiKey → 401; exhaust → 500 with message; `dumpDiagnostics()` like mock_anthropic.

- [ ] **Step 2: L1 test — ≥3 turns + tool round-trip over HTTP**

```dart
test('simple actor completes three text turns on chat completions', () async {
  final server = MockModelGatewayServer(
    engine: ScenarioEngine({
      'k': MockScenario(turns: [
        TextTurn('r1'), TextTurn('r2'), TextTurn('r3'),
      ]),
    }),
  );
  await server.start();
  // POST 3x to /v1/chat/completions with Authorization: Bearer k
  // assert bodies contain r1/r2/r3 and requestLog length == 3
  await server.stop();
});
```

- [ ] **Step 3: PASS → Commit**

```bash
git add tools/mock_model_gateway client/pubspec.yaml
git commit -m "feat(mock-gateway): HTTP server and L1 turn coverage"
```

---

### Task 6: Shared scenario recipes (≥3 texts + collab)

**Files:**
- Create: `tools/mock_model_gateway/lib/scenarios/simple_3turn.dart`
- Create: `tools/mock_model_gateway/lib/scenarios/mixed_collab_3plus.dart`
- Create: `tools/mock_model_gateway/lib/scenarios/native_collab_3plus.dart`
- Create: `tools/mock_model_gateway/test/scenarios_test.dart`

- [ ] **Step 1: Define actor keys**

Reuse `lead-script` / `worker-script` (or rename once and update harness). Simple seat: `simple-script`.

- [ ] **Step 2: `simple_3turn` — three `TextTurn`s with distinct markers**

e.g. `MARK_A1`, `MARK_A2`, `MARK_A3` (stable strings for PTY + bubble matchers).

- [ ] **Step 3: `mixed_collab_3plus` — logical toolRefs**

Port ping/pong semantics from `ping_pong_mixed_claude.dart` but use `toolRef: 'teambus.send_message'` etc., and ensure **≥3 TextTurn** markers across lead+worker combined visible replies (spec: ≥3 model replies on the path — for collab, require ≥3 assistant texts total that the selected seat’s thread will show, **and** at least one operator History compose send producing a user bubble). Document in recipe file comment which seat the L2 compose targets.

Minimum shape:

- Lead: tool uses + `TextTurn('MARK_LEAD_1')` … enough texts
- Worker: waits/sends + texts
- After bus exchange, lead/worker produce remaining markers so the **compose seat** ends with ≥3 assistant bubble texts.

- [ ] **Step 4: `native_collab_3plus`** — `native.*` toolRefs for Claude/flashskyai native team tools (map in profile). ≥3 texts + dispatch/reply/close.

- [ ] **Step 5: Unit-test recipe lengths / marker presence → Commit**

```bash
git commit -m "feat(mock-gateway): add simple/native/mixed scenario recipes"
```

---

### Task 7: `CliTestProfile` + tool name maps

**Files:**
- Create: `client/test/integration/support/cli_test_profile.dart`
- Create: `client/test/integration/support/cli_test_profile_test.dart`

- [ ] **Step 1: Define profile API**

```dart
abstract final class CliTestProfiles {
  static CliTestProfile forTool(CliTool tool) => ...;
}

final class CliTestProfile {
  const CliTestProfile({
    required this.tool,
    required this.wire, // anthropic | openaiChat | openaiResponses | cursor
    required this.resolveBinary,
    required this.toolName,
    required this.assistantVisibleMarkers,
    required this.bootToPrompt,
    // ...
  });

  bool get supportsNativeTeam =>
      CliToolRegistry.builtIn().supportsNativeTeam(tool);

  final String Function(String toolRef) toolName;
  final List<String> assistantVisibleMarkers; // from recipe
}
```

- [ ] **Step 2: Implement maps for all five CLIs**

Claude: `teambus.X` → `mcp__teammate-bus__X`.  
Codex/opencode/flashskyai: discover actual MCP tool id strings from config/docs or a one-shot probe; put mapping in profile.  
Cursor: doorbell profile; short MCP names as discovered.

- [ ] **Step 3: Tests for native flag + one toolName mapping each → Commit**

```bash
git commit -m "test: add CliTestProfile with toolRef maps"
```

---

### Task 8: Matrix harness + chat thread assertions

**Files:**
- Create: `client/test/integration/support/cli_message_matrix_harness.dart`
- Create: `client/test/integration/support/chat_thread_assertions.dart`
- Reuse: `post_frame_test_harness.dart`, pieces of `mixed_team_integration_harness.dart` (providers, ChatCubit wiring, AppStorage)

- [ ] **Step 1: `chat_thread_assertions.dart`**

Helpers:

- `expectUserBubble(AiHistoryCubit, text)`
- `expectAssistantMarkers(AiHistoryCubit, markers)` — ≥3
- `expectMailboxQueuedThenSticky(...)` when channel is mailbox
- `dumpThread(AiHistoryCubit)` for failure messages

- [ ] **Step 2: Harness methods**

```
startGateway(recipe)
writeMockProviders(profile)  // baseUrl + apiKey actors
createCubit / open session for mode
// Homogeneous teams only: TeamProfile.cli == row CLI for every member (no cross-CLI mixed in v1)
submitCompose(text)  // prefer submitSessionHistoryReviewMessage + production cubits first;
                     // pump SessionChatView when that is stable (widget pump has little prior art)
waitForGatewayTurns / waitForPtyMarkers / waitForBubbles
diagnosticsBundle() on failure
```

Must **not** call `deliverMemberStdin` as the operator send.

**Mailbox vs PTY bubble asserts:** after `submitCompose`, use
`resolveHistoryContinueChannel(...)` (same inputs as production). If result is
`mailbox`, assert Queued → sticky user bubble; if `pty`, assert optimistic /
transcript user bubble. Always assert ≥3 assistant markers.

- [ ] **Step 3: Unit-test thread assertion helpers with fake cubit state if feasible → Commit**

```bash
git commit -m "test: add CLI message matrix harness and bubble assertions"
```

---

### Task 8b: Retarget legacy mixed harness to gateway (before deleting mock_anthropic)

**Files:**
- Modify: `client/test/integration/support/mixed_team_integration_harness.dart`
- Modify: `client/test/integration/support/mixed_team_task_scenario.dart`
- Modify: `client/test/integration/support/mixed_team_idle_busy_l2_scenario.dart`
- Modify: `client/test/integration/mixed_team_claude_*_integration_test.dart`
- Modify: `client/test/integration/mixed_team_claude_docker_integration_test.dart` (L3 — keep green or explicitly skip with reason; L3 is not a matrix gate)

- [ ] **Step 1: Replace `MockAnthropicServer` / `package:mock_anthropic` imports with `MockModelGatewayServer` + Anthropic wire + ported recipes**

Keep existing L2 task / idle-busy / docker test behavior; only swap the mock backend. Port these legacy scenarios into `tools/mock_model_gateway/lib/scenarios/` (separate from matrix `*_3plus` recipes):

- `ping_pong_mixed_claude`
- `task_dispatch_mixed_claude`
- `task_complete_mixed_claude`
- `mail_priority_mixed_claude`
- `doorbell_dispatch_mixed_claude`

Use logical `toolRef` + Claude profile mapping (same engine as matrix).

- [ ] **Step 2: Run existing Claude mixed L2 (+ docker if available) green**

```bash
cd client && flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test \
    test/integration/mixed_team_claude_bus_integration_test.dart \
    test/integration/mixed_team_claude_tasks_integration_test.dart \
    test/integration/mixed_team_claude_idle_busy_integration_test.dart \
    --tags "integration && linux-pty"

# Optional L3 (Docker):
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/mixed_team_claude_docker_integration_test.dart \
  --tags "integration && docker"
```

- [ ] **Step 3: Commit**

```bash
git commit -m "test: point mixed team harness at mock_model_gateway"
```

**Do not** delete `mock_anthropic` until this task is green (and L3 either green on gateway or documented deferred with a remaining dep — prefer green).

---

### Task 9: L2 — Claude simple cell (first full E2E)

**Files:**
- Create: `client/test/integration/cli_message_matrix_claude_test.dart` (or `..._simple_test.dart`)
- Tags: `@Tags(['integration', 'linux-pty'])`

- [ ] **Step 1: Write failing test**

```dart
test('claude simple: History compose → user bubble → ≥3 assistant bubbles', () async {
  // skip unless claude + native pty
  // harness: simple mode + simple_3turn + anthropic wire
  // pump chat UI, submit once (or as recipe requires)
  // assert gateway log ≥3, PTY markers, user + 3 assistant bubbles
});
```

- [ ] **Step 2: Run**

```bash
cd client && flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib \
  flutter test test/integration/cli_message_matrix_claude_test.dart \
  --tags "integration && linux-pty" --plain-name "claude simple"
```

Expected: FAIL (missing wiring) or product red.

- [ ] **Step 3: Implement harness wiring for Claude simple until green**

If product bug (no bubble / no deliver): fix product, re-run. Do not soften asserts.

- [ ] **Step 4: Commit**

```bash
git commit -m "test: claude simple message matrix cell green"
```

---

### Task 10: L2 — Claude mixed cell (migrate off mock_anthropic)

**Files:**
- Extend: `cli_message_matrix_claude_test.dart`
- Modify existing mixed tests to use gateway **or** delete once this cell covers ping/pong+bubbles
- Update imports away from `package:mock_anthropic/...`

- [ ] **Step 1: Failing mixed test with `mixed_collab_3plus` + History compose on lead seat**

Assert bus mail + ≥3 assistant bubbles on compose seat + PTY markers.

- [ ] **Step 2: Green → fix product if needed → Commit**

```bash
git commit -m "test: claude mixed message matrix cell on mock gateway"
```

- [ ] **Step 3: Point old `mixed_team_claude_*` tests at gateway or remove duplicates (same commit or follow-up)**

Prefer delete/redirect to avoid dual-track.

---

### Task 11: L2 — Claude native cell

- [ ] **Step 1: Failing native test with `native_collab_3plus`**
- [ ] **Step 2: Green (product fixes in scope) → Commit**

```bash
git commit -m "test: claude native message matrix cell green"
```

---

### Task 12: L2 — flashskyai (openai wire) simple + native + mixed

**Files:**
- Create: `client/test/integration/cli_message_matrix_flashskyai_test.dart`
- Profile: `provider_type: openai`, OpenAI Chat adapter

- [ ] **Step 1: simple cell → green**
- [ ] **Step 2: mixed cell → green**
- [ ] **Step 3: native cell → green**
- [ ] **Step 4: Commit per cell or one commit when all three green**

```bash
git commit -m "test: flashskyai message matrix cells green"
```

---

### Task 13: L2 — codex simple + mixed (native N/A)

**Files:**
- Create: `client/test/integration/cli_message_matrix_codex_test.dart`
- Wire: OpenAI Responses

- [ ] **Step 1: simple → green (fix product/boot as needed)**
- [ ] **Step 2: mixed → green**
- [ ] **Step 3: Explicit test that native is skipped with reason**

```dart
test('codex native is N/A', () {
  expect(CliTestProfiles.forTool(CliTool.codex).supportsNativeTeam, isFalse);
});
```

- [ ] **Step 4: Commit**

```bash
git commit -m "test: codex simple/mixed message matrix cells green"
```

---

### Task 14: L2 — opencode simple + mixed

Same pattern as Task 13 with OpenAI Chat adapter.

```bash
git commit -m "test: opencode simple/mixed message matrix cells green"
```

---

### Task 15: Cursor wire discovery + L2 simple + mixed

**Files:**
- Create: `tools/mock_model_gateway/lib/wire/cursor_adapter.dart` (after spike)
- Create: `client/test/integration/cli_message_matrix_cursor_test.dart`
- Document redirect + fake creds in `CliTestProfile` comments / DEVELOPMENT.md

- [x] **Step 1: Spike (time-box ≤2h)** — **BLOCKED** 2026-07-22 (cursor-agent `2026.07.17-3e2a980`). Public binary cannot route model traffic to loopback without Cursor cloud. Findings recorded in `CliTestProfile` (`_cursorGatewayRedirectSpikeNotes` / `gatewayRedirectNotes`). Summary:
  - No public `--base-url`; auth is Cursor cloud (`--api-key` / `CURSOR_API_KEY`).
  - Hidden `agent-cli-local` (`--base-url`, `--authless`, `CURSOR_LOCAL_AGENT_BASE_URL`) is in-bundle but gated on injected `localAgentRuntime` — public entry is `P({})` → always rejected.
  - `CURSOR_API_ENDPOINT` retargets ConnectRPC `aiserver.v1` only (not OpenAI/Anthropic).
  - Product preset is account-only (`baseUrl: ''`).
- [ ] **Step 2: Implement Cursor WireAdapter + L0/L1 tests** — **deferred** (blocked on spike)
- [ ] **Step 3: simple cell → green (doorbell-aware)** — **deferred** (blocked)
- [ ] **Step 4: mixed cell → green (doorbell + short MCP; no long wait_for_message script)** — **deferred** (blocked)
- [ ] **Step 5: Commit** — no green commit; escalate to human (do not fake green)

```bash
git commit -m "test: cursor simple/mixed message matrix cells green"
```

If spike proves redirect impossible without cloud: **stop and escalate to human** with findings — do not fake a green cell. **← triggered.**

---

### Task 16: Retire `mock_anthropic` + docs

**Precondition:** Task 8b green — `rg mock_anthropic` is empty (including L3 on gateway or documented deferral).

**Files:**
- Delete or gut: `tools/mock_anthropic/`
- Modify: `client/pubspec.yaml` — remove `mock_anthropic`
- Grep and fix remaining imports
- Modify: `docs/DEVELOPMENT.md` — L0/L1/L2 commands for gateway + matrix tags
- Modify: any CI workflows that reference `mock_anthropic`

- [ ] **Step 1: Grep `mock_anthropic` — zero references**
- [ ] **Step 2: Update DEVELOPMENT.md**

Document (package `dart test` **is** L1 — no duplicate client L1 required unless flutter_test is needed):

```bash
cd tools/mock_model_gateway && dart test          # L0 + L1 (HTTP)
# L2 matrix:
cd client && flutter build linux --debug
LD_LIBRARY_PATH=... flutter test --tags "integration && linux-pty" \
  test/integration/cli_message_matrix_*.dart
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: retire mock_anthropic; document mock gateway matrix"
```

---

### Task 17: Matrix completion checklist + regression smoke

- [ ] **Step 1: Fill this table with pass evidence (command + date) in the PR description**

| CLI | simple | native | mixed |
|-----|--------|--------|-------|
| claude | | | |
| flashskyai | | | |
| codex | | N/A | |
| opencode | | N/A | |
| cursor | **BLOCKED** (no loopback redirect; Task 15 spike) | N/A | **BLOCKED** (same) |

- [ ] **Step 2: Deliberate break smoke (one cell)**

Temporarily break History submit or bubble append; confirm cell fails with thread/gateway dump; revert.

- [ ] **Step 3: Final commit if doc-only updates remain**

```bash
git commit -m "docs: record CLI message matrix completion evidence"
```

---

## Execution notes

- **Order matters:** Tasks 1–8 → **8b** → 9–15 → 16–17. Tasks 12–14 may proceed in parallel after Task 9 proves the E2E path; Task 15 (Cursor) must not block them.
- **Product fixes:** land in the same workstream as the red cell; mention in commit body (`fix:` / `test:` as appropriate).
- **Cursor:** Task 15 may unblock other CLIs — do not block Tasks 12–14 on Cursor spike.
