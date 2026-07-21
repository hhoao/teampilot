# Mock Model Gateway + CLI message matrix: design

## Problem

Message-send integration coverage is incomplete and uneven:

- Claude mixed TeamBus L2 tests already use `tools/mock_anthropic`, but other
  CLIs either lack model mocks or only probe PTY paste/ACK against whatever
  provider the local install hits.
- There is no shared matrix across **simple / native / mixed** for all launch
  CLIs, so send-path regressions (PTY inject, mailbox, doorbell) and multi-turn
  team collaboration are easy to miss.
- Extending mocks per CLI as one-off packages does not scale as more CLIs are
  added.

## Goal

- Provide a **protocol-pluggable Mock Model Gateway** so real CLI processes talk
  only to loopback — never the operator’s local or cloud API servers.
- Cover a **CLI × mode matrix** with scripted scenarios of **≥3 model replies**,
  including **team collaboration** where the mode supports it.
- Assert the **full operator chat path**, not just PTY/backend delivery:
  compose in the session chat UI → deliver (PTY or mailbox) → **user + assistant
  bubbles** appear in the History / chat thread (including Queued → sticky
  mailbox user bubbles when that channel is used).
- On failure: emit enough gateway / PTY / bus / **thread** evidence to
  **attribute the fault** (wire, scenario, product send path, chat UI, or boot
  profile) and fix — do not skip to hide reds.

## Non-goals

- Hitting real vendor APIs in CI or local matrix runs.
- Pixel / golden UI snapshot testing (assert **semantic** bubble presence via
  widget finders / cubit state, not screenshots).
- Making Docker SSH (L3) a required cell of the matrix in the first delivery.
- Preserving `tools/mock_anthropic` package name or HTTP surface for
  compatibility (replace / migrate freely).
- Landing-page first-prompt compose (matrix kickoff uses the **in-session
  History compose** path; landing can reuse harness later).

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Mock architecture | Unified multi-protocol gateway + shared ScenarioEngine |
| Scenario depth | ≥3 replies; collaboration scripts for native + mixed |
| CLI scope | All five: claude, flashskyai, codex, opencode, cursor |
| Mode matrix | Full simple / native / mixed |
| Native for non-native CLIs | **N/A** (skip) for codex, opencode, cursor — only simple + mixed |
| Operator send surface | **Session chat History compose** (`SessionChatView` / submit path) |
| Thread observation | User + assistant bubbles in chat thread (cubit / finders) |
| Compat / effort | Prefer extensibility; no backward-compat constraint |

## Coverage matrix

| CLI | simple (≥3 turns) | native (collab ≥3) | mixed (TeamBus collab ≥3) |
|-----|-------------------|--------------------|---------------------------|
| claude | yes | yes | yes |
| flashskyai (openai wire) | yes | yes | yes |
| codex | yes | N/A | yes |
| opencode | yes | N/A | yes |
| cursor | yes | N/A | yes (doorbell bus path) |
| future CLI | register WireAdapter + CliTestProfile | only if `NativeTeamCapability` | only if bus-capable |

N/A cells: `CliTestProfile.supportsNativeTeam == false` → `markTestSkipped` with
an explicit reason; document in the matrix, do not pretend the cell passes.

**Homogeneous teams:** mixed/native matrix cells use one CLI for every roster
member (`TeamProfile.cli` = row CLI; no cross-CLI mixed in v1). Cross-CLI mixed
is a later matrix expansion.

**flashskyai wire:** L2 cells pin `provider_type: openai` (OpenAI Chat adapter).
Anthropic-mode flashskyai is out of v1 matrix scope (can reuse Anthropic adapter
later as a separate row if needed).

## Architecture

```
tools/mock_model_gateway/
  core/       ScenarioEngine (actor-keyed turns, request log)
  wire/       AnthropicMessages | OpenAIChat | OpenAIResponses | … (pluggable)
  scenarios/  simple_3turn | native_collab_3plus | mixed_collab_3plus | …
  bin/        mock_model_gateway.dart
```

### ScenarioEngine (protocol-agnostic)

Actors (leader / worker / simple seat) bind to an **apiKey** (or equivalent
`actorId`). Turns:

| Turn | Role |
|------|------|
| `Text(content)` | Visible assistant reply |
| `ToolUse(toolRef, input, id?)` | Emit tool call via **logical** `toolRef` (not raw wire name) |
| `AssignedTaskUpdate(id, toolRef, status, result?)` | Resolve task id from inbound tool_result (same behavior as today’s `AssignedTaskUpdateTurn` in `mock_anthropic`), then emit update via mapped `toolRef` |
| `WaitUntil(predicate)?` | **Deferred in v1 recipes** — initial `*_3plus` scripts ship without it; add only when a concrete collab sync need appears |

**Logical tool refs:** recipes use stable ids such as
`teambus.send_message`, `teambus.wait_for_message`, `native.TeamCreate`.
`CliTestProfile.toolName(toolRef) → String` maps to the CLI’s on-wire name
(e.g. Claude `mcp__teammate-bus__send_message`, OpenCode/Codex equivalent MCP
tool id). The Engine emits the mapped name through the WireAdapter. **Do not**
fork recipes per CLI for naming differences.

Rules:

- Each matrix path advances **≥3 model replies** (a turn that includes visible
  text counts; pure tool-only turns may appear but do not alone satisfy the
  three-reply floor unless the recipe explicitly counts them — recipes must
  still produce ≥3 user-visible assistant texts).
- **Scenario exhausted** → gateway returns a clear 5xx + log; tests fail loudly.
- **Request log**: `(actorId, wire, path, turnIndex, turnLabel, at)`.

### Wire adapters

`WireAdapter` maps Engine turns ↔ HTTP/SSE for one wire:

- Anthropic Messages (`/v1/messages`) — claude
- OpenAI Chat Completions — opencode, flashskyai (v1 pinned openai), others as needed
- OpenAI Responses — codex default `wire_api`
- Cursor — dedicated adapter; redirect traffic to loopback via whatever the CLI
  accepts (custom base URL and/or auth/HOME injection). Profile must document
  the exact redirect + fake credential steps so L2 never hits Cursor cloud.

New CLI = new or reused WireAdapter + harness provider pointing `baseUrl` (or
CLI-specific auth) at the gateway. **Do not** fork the scenario DSL per CLI.

### Scenario recipes (shared semantics)

| Recipe | Mode | Minimum behavior |
|--------|------|------------------|
| `simple_3turn` | simple | History compose send → ≥3 assistant texts in thread |
| `native_collab_3plus` | native (claude / flashskyai only) | Lead dispatch → worker reply → lead close-out; ≥3 visible replies + native team tools |
| `mixed_collab_3plus` | mixed | Lead `send_message` → worker reply → lead confirm; TeamBus tool_use. Cursor uses **doorbell + short MCP**, not long-blocking `wait_for_message` scripts |

### End-to-end operator path (required for L2)

Each matrix cell drives the **real chat UI submit path**, not a harness-only
`deliverMemberStdin` shortcut:

```
SessionChatView compose
  → submitSessionHistoryReviewMessage / History continue
  → PTY inject  OR  mailbox deliverUserCommand
  → AiHistoryCubit thread:
       PTY: optimistic/pending user bubble → assistant bubbles from live
            transcript refresh
       mailbox: Queued strip → sticky local user bubble after consume;
            assistant bubbles when the seat’s transcript advances
```

Product-side assertions (wire-independent), **all required**:

1. Gateway: actor completed ≥3 turns; no exhausted / decode errors in log.
2. Bus (mixed): mail/task assertions (reuse `bus_*_assertions`).
3. **PTY probe** — `CliTestProfile.assistantVisibleMarkers` in the member
   terminal grid (proves the CLI actually produced the scripted text).
4. **Chat thread bubbles** — after compose submit:
   - **User bubble** for the operator text (pending, sticky mailbox, or
     reconciled transcript user message — whichever the channel produces).
   - **≥3 assistant bubbles** (or equivalent thread items carrying the
     scripted assistant texts) visible via `AiHistoryCubit` / widget finders
     for the selected seat.
   - Mailbox channel: Queued row appears on send; after consume, sticky user
     bubble is present (aligns with history-mixed-mailbox-continue design).

Harness may call the same submit function the UI uses with a pumped
`SessionChatView` (preferred) or an equivalent bound to production cubits —
but must not bypass compose → channel routing → thread update.

## Test layering

| Layer | What | Dependencies | Tag |
|-------|------|--------------|-----|
| L0 | ScenarioEngine + WireAdapter encode/decode | none | gateway package unit tests |
| L1 | Gateway HTTP: ≥3 turns, tool round-trips | no CLI | `integration && cross-platform` |
| L2 | Real CLI PTY + ChatCubit + **pumped chat UI** + gateway matrix | CLI on PATH + native PTY | `integration && linux-pty` |
| L3 | mixed + Docker SSH worker (optional later) | Docker | `integration && docker` |

First delivery: **L0–L2**. L3 follows existing Docker patterns and is not a
matrix gate.

### Harness

Parameterize by recipe, not by copy-paste per CLI:

```
CliMessageMatrixHarness
  .forCli(CliTool)
  .mode(simple | native | mixed)
  .scenario(simple_3turn | native_collab_3plus | mixed_collab_3plus)
  → startGateway / writeMockProviders / launchSession
  → pump SessionChatView (History compose)
  → submit via UI (or production submit binding)
  → assert gateway + PTY markers + thread bubbles
```

`CliTestProfile` holds: binary resolution, **boot-gate dismissal** (trust
screens, API-key prompts, `customApiKeyResponses`, update modals, …),
boot-to-prompt detection, fullscreen deliver behavior, `supportsNativeTeam`,
bus style (long-wait vs doorbell), `toolName(toolRef)`,
`assistantVisibleMarkers`, **thread bubble matchers** (user text + assistant
marker texts), and gateway credential / baseUrl wiring.

Migrate / replace `MixedTeamIntegrationHarness` and standalone deliver tests
into this path — **no dual-track** mock stacks.

### Failure diagnosis loop

On failure, always surface:

1. Gateway request log (actor, wire, turnIndex, turnLabel)
2. Scenario progress (expected next turn vs exhausted / decode error)
3. Last PTY probe frame + which `assistantVisibleMarkers` were missing
4. **Thread dump** — pending / sticky / committed user + assistant items for
   the seat (and Queued strip state when mailbox)
5. Bus assertion detail (mixed)

Attribution order:

1. Wire / protocol → fix Adapter  
2a. Wrong on-wire tool **name** → fix `CliTestProfile.toolName` mapping  
2b. Wrong tool **args / turn content** → fix recipe  
3. Deliver works (gateway + PTY) but **no / wrong bubbles** → fix History
   continue, live refresh, or mailbox Queued→sticky path  
4. Send path never reaches CLI (PTY inject / mailbox / doorbell) → fix product
   deliver  
5. CLI boot / trust screens → fix `CliTestProfile` boot-gate

`CliTestProfile.supportsNativeTeam` should **derive** from
`CliToolRegistry.supportsNativeTeam` (or equivalent production capability), not
a hand-maintained duplicate flag.

**Do not skip to hide reds.** Allowed skips: missing local binary; N/A native
cell.

## Extensibility

To add a CLI later:

1. Implement or reuse a `WireAdapter`.
2. Add `CliTestProfile` (boot, deliver, bus style, native flag).
3. Point provider credentials at the gateway.
4. Enable matrix cells that the capabilities allow.

No change to ScenarioEngine or shared recipes unless the collaboration
semantics themselves change.

## Migration

- Introduce `tools/mock_model_gateway` as the sole mock stack for matrix tests.
- Move useful Anthropic scenarios from `mock_anthropic` into
  `scenarios/` (rewritten against the shared DSL as needed).
- Delete or gut `mock_anthropic` once L2 Claude paths run on the gateway — no
  compatibility shim required.

## Success criteria

- L0–L1 green without any vendor CLI.
- L2 matrix green for every non-N/A cell on a machine with the five CLIs +
  Linux PTY build, using **only** the mock gateway as model backend.
- Each L2 cell proves: History compose submit → user bubble → ≥3 assistant
  bubbles (plus mailbox Queued→sticky when that channel is exercised).
- A deliberate product send-path or thread-bubble break fails the matching cell
  with logs that point at send path / thread (not flaky timeout alone).
- Documented run commands in `docs/DEVELOPMENT.md` for L0/L1/L2 filters.
