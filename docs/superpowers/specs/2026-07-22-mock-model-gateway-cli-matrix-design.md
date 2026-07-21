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
- On failure: emit enough gateway / PTY / bus evidence to **attribute the fault**
  (wire, scenario, product send path, or boot profile) and fix — do not skip to
  hide reds.

## Non-goals

- Hitting real vendor APIs in CI or local matrix runs.
- Pixel / UI snapshot testing.
- Making Docker SSH (L3) a required cell of the matrix in the first delivery.
- Preserving `tools/mock_anthropic` package name or HTTP surface for
  compatibility (replace / migrate freely).

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Mock architecture | Unified multi-protocol gateway + shared ScenarioEngine |
| Scenario depth | ≥3 replies; collaboration scripts for native + mixed |
| CLI scope | All five: claude, flashskyai, codex, opencode, cursor |
| Mode matrix | Full simple / native / mixed |
| Native for non-native CLIs | **N/A** (skip) for codex, opencode, cursor — only simple + mixed |
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
| `AssignedTaskUpdate(...)` | Resolve task id from inbound tool_result, then update |
| `WaitUntil(predicate)?` | Optional sync before advancing (collab) |

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
| `simple_3turn` | simple | Operator send → ≥3 assistant texts |
| `native_collab_3plus` | native (claude / flashskyai only) | Lead dispatch → worker reply → lead close-out; ≥3 visible replies + native team tools |
| `mixed_collab_3plus` | mixed | Lead `send_message` → worker reply → lead confirm; TeamBus tool_use. Cursor uses **doorbell + short MCP**, not long-blocking `wait_for_message` scripts |

Product-side assertions (wire-independent):

1. Gateway: actor completed ≥3 turns; no exhausted / decode errors in log.
2. Bus (mixed): mail/task assertions (reuse `bus_*_assertions`).
3. **Primary L2 observation: PTY probe** — `CliTestProfile` defines
   `assistantVisibleMarkers` (substring / regex list) expected in the member
   terminal grid after the recipe. History / transcript adapters are **out of
   v1 assertion path** (optional later); do not block matrix cells on History
   UI.

## Test layering

| Layer | What | Dependencies | Tag |
|-------|------|--------------|-----|
| L0 | ScenarioEngine + WireAdapter encode/decode | none | gateway package unit tests |
| L1 | Gateway HTTP: ≥3 turns, tool round-trips | no CLI | `integration && cross-platform` |
| L2 | Real CLI PTY + ChatCubit + gateway matrix | CLI on PATH + native PTY | `integration && linux-pty` |
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
  → startGateway / writeMockProviders / launchSession / kickoff / assert
```

`CliTestProfile` holds: binary resolution, **boot-gate dismissal** (trust
screens, API-key prompts, `customApiKeyResponses`, update modals, …),
boot-to-prompt detection, fullscreen deliver behavior, `supportsNativeTeam`,
bus style (long-wait vs doorbell), `toolName(toolRef)`,
`assistantVisibleMarkers`, and gateway credential / baseUrl wiring.

Migrate / replace `MixedTeamIntegrationHarness` and standalone deliver tests
into this path — **no dual-track** mock stacks.

### Failure diagnosis loop

On failure, always surface:

1. Gateway request log (actor, wire, turnIndex, turnLabel)
2. Scenario progress (expected next turn vs exhausted / decode error)
3. Last PTY probe frame + which `assistantVisibleMarkers` were missing
4. Bus assertion detail (mixed)

Attribution order:

1. Wire / protocol → fix Adapter  
2. Scenario vs real MCP tool names/args → fix recipe  
3. Send path (PTY inject / mailbox / doorbell) → fix product  
4. CLI boot / trust screens → fix `CliTestProfile`

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
- A deliberate product send-path break fails the matching cell with logs that
  point at send path (not flaky timeout alone).
- Documented run commands in `docs/DEVELOPMENT.md` for L0/L1/L2 filters.
