# Matrix RosterShape + native replicated collab (design)

**Date:** 2026-08-04  
**Status:** Approved for planning (decided by product owner: best architecture, no compat)  
**Scope:** Add a third matrix axis `RosterShape` for CLI message integration tests; ship first L2 cell `claude × native × replicated` with full-path multi-turn assertions (CLI roster identity + worker consume/reply). Fix product bugs uncovered while greening the cell. No backward/forward compatibility requirements.

## Problem

1. Claude native L2 matrix only covers **singleton** roster (`team-lead` + one worker). It never expands `replicas`, never asserts pod-level Claude `config.json` / inboxes, and does not prove members receive `SendMessage` across turns.
2. The bug class “type roster vs session pods” (lead writes `developer.json`, shells poll `developer-0`) was fixed in product code but **not** guarded by an L2 cell.
3. `CliMessageMatrixHarness.bootAllMembersToPrompt` iterates `team.members` (types), so a naive `replicas: 2` would still boot wrong ids — shape awareness must live in the harness, not one-off tests.

## Goals

1. Matrix becomes **CLI × Mode × RosterShape** with a clear extension point for future cells (flashskyai native replicated, mixed placement-filtered, etc.).
2. First green cell: **claude × native × replicated**, multi-turn proof with explicit round shape:
   - **Lead compose round 1** → disk roster/inbox identity → **worker-0** consume + reply marker.
   - **Lead compose round 2** → lead second-round marker (channel still works after worker reply).
   - This is **two lead History composes + one worker response**, not two full bidirectional ping-pongs.
3. Harness APIs take `RosterShape` so session create, boot, compose seat, and assertions share one pod list (`sessionRosterMembers` / `cliTeamRosterMembers` semantics).
4. Product defects found while greening are fixed in the same effort (no compat shims).

## Non-goals

- Shipping L2 cells for every CLI×shape combination in this change.
- SSH / Docker placement (Machines remote) — local only.
- Type-name SendMessage aliases.
- Idle doorbell / `teammateMode` redesign unless required to green the cell.
- Preserving old matrix helper signatures or docs layout for compatibility.

## Locked decisions

| Topic | Decision |
|-------|----------|
| Architecture | Approach 2: `RosterShape` axis + separate gateway recipe + assertion modules |
| First cell | `claude × native × replicated` |
| Proof depth | Full path (disk identity **and** worker behavior); **2 lead composes + 1 worker reply** |
| Compat | None — rename/split harness APIs and MATRIX docs as needed |
| `placementFiltered` | API + unit tests only; L2 cell deferred (explicit skip / not registered) |

## Architecture

### RosterShape

```dart
enum RosterShape {
  /// Lead + one worker type with replicas=1 (today’s matrix teams).
  singleton,

  /// Worker type replicas≥2 → session/CLI pods `type-0`, `type-1`, …
  replicated,

  /// Session bindings omit some expanded pods (Machines / placement).
  /// First ship: shape builders + unit tests only; no L2 cell.
  placementFiltered,
}
```

**Applicability**

| Mode \ Shape | singleton | replicated | placementFiltered |
|--------------|-----------|------------|-------------------|
| simple | N/A (ignore) | N/A | N/A |
| native | existing cell | **this change** | deferred L2 |
| mixed | existing cell | later | deferred L2 |

### Matrix cell identity

A cell is `(CliTool, CliMatrixMode, RosterShape)` plus a gateway recipe.

- Existing tests become `shape: RosterShape.singleton` (default).
- New test: `claude native replicated` with recipe `nativeCollabReplica2Plus`.

Update [docs/MATRIX.md](../MATRIX.md) to a 3D or nested table (no need to keep the 2026-07-22 2D table shape).

### Harness responsibilities

Extend `CliMessageMatrixHarness` (or split if file size warrants — prefer focused helpers under `test/integration/support/`):

| API | Behavior |
|-----|----------|
| `RosterShape shape` | Constructor / factory param; default `singleton` |
| `buildHomogeneousTeam()` | Emit type roster for shape (`developer.replicas=2` for replicated; lead always singleton) |
| `expectedPodIds` | Lead + pods after expand / session bindings |
| `openSession` | `createSession` must materialize **pods** (use same expansion path as production: `rosterMembers` types → session bindings). After open, prefer `sessionRosterMembers(session, team)` for boot lists |
| `bootAllMembersToPrompt` | Iterate **session pods**, not `team.members` types |
| `primaryWorkerPodId` | e.g. `developer-0` for replicated; `worker-1` / singleton worker id for singleton |

**Breaking change (intentional):** `bootAllMembersToPrompt` must not silently ignore replicas. Call sites that assumed type ids must pass through pod ids.

Worker member **type** id for replicated cells: `developer` (aligns with product default native team and prior bug). Singleton cells may keep `worker-1` or migrate to `developer` — **decide in implementation: migrate singleton native/mixed matrix worker id to `developer`** for one naming scheme (no compat). Update gateway scripts / mail assertions accordingly.

### Gateway recipes

| Recipe | Shape | Role |
|--------|-------|------|
| `nativeCollab3Plus` | singleton | Keep for regression (may rename worker ids) |
| `nativeCollabReplica2Plus` | replicated | **New** — lead addresses `developer-0` (and optionally ignores `developer-1` or fans work later); worker-0 script consumes + replies; second lead turn confirms continued channel |

Replica recipe requirements:

1. Lead turn 1: tools that write team/task + `SendMessage` / native equivalent **to `developer-0`** (not bare `developer`).
2. Worker-0: consume → `MARK_REPLICA_W0_1` → reply to lead.
3. Lead turn 2: observe reply path / second `SendMessage` → `MARK_REPLICA_LEAD_2`.
4. Optional: `developer-1` stays idle (proves targeting is pod-specific).

Map `native.*` toolRefs through existing `CliTestProfile` tool name tables.

Provider keys: keep lead/worker script API keys; replicated worker-0 uses `workerScriptApiKey` (or a dedicated `worker0ScriptApiKey` if both pods need scripts — prefer one active worker pod for first cell).

### Assertions module

New `native_roster_assertions.dart` (integration support):

- `expectClaudeRosterPods(sessionRuntimeClaudeDir, cliTeamName, expectedNames)`
- `expectClaudeInboxExists(…, podId)` / `expectClaudeInboxAbsent(…, typeId)`
- Optional: unread count ≥ 1 before worker consumes; after consume, read flag or empty per Claude semantics observed in the wild

Chat/PTY: reuse `waitForPtyMarkers` on lead and worker-0 shells.

### Product fix policy

While greening the cell, if failures are due to product bugs (roster staging, boot list, agent-id, inbox poll, etc.), fix at the root in app code under the same branch. Do not weaken assertions to green the test. No deprecated dual-write of type+pod inboxes.

Known risk areas:

- Harness/product iterating types instead of pods for connect/boot.
- Gateway/tool input using type names after roster is pod-based.
- Member idle without consuming inbox (only fix if required for this cell’s proof depth).

## Data flow (first cell)

```
RosterShape.replicated
  → team types: team-lead + developer(replicas=2)
  → createSession → bindings developer-0, developer-1
  → stage Claude config/inboxes for pods
  → bootAll pods to prompt
  → History compose on lead (round 1)
  → assert disk roster/inbox identity
  → wait worker-0 markers + lead markers
  → History compose on lead (round 2)
  → assert second-round markers / gateway turns
```

## Testing plan

1. **Unit:** `RosterShape` team builder → expected type replicas and pod ids; `placementFiltered` binding omit list.
2. **Unit:** harness helpers (`expectedPodIds`, boot member list) without PTY.
3. **L2:** `cli_message_matrix_claude_test.dart` — new test for replicated full path; existing native test pinned to `singleton`.
4. **Docs:** rewrite MATRIX.md status for shape axis; document how to add flashskyai replicated later (recipe + one test registration).

## Acceptance (claude native replicated)

1. Session members include `team-lead`, `developer-0`, `developer-1`.
2. Claude `teams/<cliTeam>/config.json` names match those pods; `agentType` for pods is `developer`.
3. `inboxes/developer-0.json` used for lead→worker traffic; type-level `inboxes/developer.json` is not the live target for this session write path.
4. Worker-0 emits round-1 marker; lead completes round-2 marker after further compose.
5. `developer-1` is booted but not required to act (documents pod-specific addressing).

## Implementation notes

- Prefer small support files over growing `cli_message_matrix_harness.dart` past maintainability (~split roster/shape builders if needed).
- Mock gateway scenarios live under `tools/mock_model_gateway/lib/scenarios/`.
- Tags remain `@Tags(['integration', 'linux-pty'])` for the new cell.
- No need to preserve old commit evidence rows in MATRIX.md; replace with current structure.
