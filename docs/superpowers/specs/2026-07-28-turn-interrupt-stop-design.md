# Turn interrupt (Stop) on conversation compose

## Goal

On the conversation page compose bar, when the **currently selected member** is mid-turn (`working`), swap Send for **Stop**. Stop aborts that member’s in-flight agent turn and leaves the session / PTY connected so the user can continue chatting.

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product intent | Stop **current generation** (not disconnect / close tab / delete history) |
| UI placement | Compose circular action: Send ↔ Stop (ChatGPT-style) |
| Interrupt scope | **Selected member only** (Simple = sole seat) |
| Busy signal for Stop chrome | Selected member `availability == working` — **not** session-level `workingSessionIds` |
| Interrupt transport | PTY write sequence from per-CLI capability |
| Claude / first-wave CLIs | **Ctrl+C** (`\x03`) via capability (not Esc) |
| Architecture | New `TurnInterruptCapability` on CLI registry; no scattered `if (cli == …)` |
| In-flight inject | Cancel that member’s PTY inject **before** writing interrupt bytes |
| Unsupported / disconnected | Silent no-op (+ debug log); do not toast |

## Non-goals

- Disconnect / Restart / Resource Manager kill
- Closing the workbench tab or deleting the session record
- Interrupting every working member in a team session
- CLI-specific Esc (or multi-step) sequences in v1 — capability API must allow them later; v1 defaults all built-ins to `['\x03']`
- Changing how `workingSessionIds` is computed for the sidebar

## Problem

Users can stop a turn only by focusing the embedded terminal and pressing keys (or using disconnect). There is no compose-level Stop, and no registry hook for “how this CLI aborts a turn,” so any ad-hoc Ctrl+C in UI would fight AGENTS.md CLI layering rules and be hard to evolve per tool.

## Design

### 1. `TurnInterruptCapability`

New capability under `client/lib/services/cli/registry/capabilities/`:

```dart
abstract interface class TurnInterruptCapability implements CliCapability {
  /// When false, compose stays on Send even if presence is working.
  bool get supportsTurnInterrupt;

  TurnInterruptPlan get interruptPlan;
}

final class TurnInterruptPlan {
  const TurnInterruptPlan({
    required this.steps,
    this.gapBetweenSteps = Duration.zero,
  });

  /// Ordered strings written to the member PTY (e.g. `['\x03']`).
  final List<String> steps;
  final Duration gapBetweenSteps;
}
```

Wire into each built-in `CliToolDefinition` via `capabilities`.

**v1 built-in plans**

| CLI | `supportsTurnInterrupt` | `steps` |
|-----|-------------------------|---------|
| Claude | true | `['\x03']` |
| flashskyai | true | `['\x03']` |
| Codex | true | `['\x03']` |
| OpenCode | true | `['\x03']` |
| Cursor | true | `['\x03']` |

Later Esc / multi-step plans change only the tool’s capability implementation.

### 2. `MemberTurnInterruptService`

Owns orchestration (constructor-injected deps; no UI):

1. Resolve open tab + member shell; if missing / not connected → no-op.
2. Cancel in-flight PTY inject for `(sessionId, memberId)` if the delivery / inject layer reports busy.
3. Resolve effective `CliTool` for that seat (same rules as launch / coordination).
4. Read `TurnInterruptCapability` from `CliToolRegistry`; if missing or `!supportsTurnInterrupt` → no-op.
5. For each `interruptPlan.steps` entry, `writeToPty`; honor `gapBetweenSteps` between steps.

Does **not** call disconnect, close tab, or mutate history.

### 3. `ChatCubit` API

```dart
Future<void> interruptSelectedMemberTurn({
  String? sessionId,
  String? memberId,
});
```

- Defaults: active tab session + that tab’s selected / continue member id (same seat compose already uses).
- Delegates to `MemberTurnInterruptService` (async so multi-step plans can honor `gapBetweenSteps`).
- Safe to call repeatedly while still `working` (idempotent re-send of the plan).
- Compose calls via `unawaited(...)` (same pattern as other fire-and-forget session actions).

### 4. Compose UI

Surface: history continue compose (`session_review_compose_card` / `session_chat_view`).

| Condition | Button |
|-----------|--------|
| Selected member `working` **and** CLI `supportsTurnInterrupt` | Stop (square icon); `onStop` → Cubit |
| Else | Existing Send (`arrow_upward` + submit / submit-lock behavior) |
| `isSubmitting` (connect / inject) without working yet | Keep current spinner / Send disabled behavior; switch to Stop once working |

l10n: Stop tooltip / a11y label in `app_en.arb` + `app_zh.arb`.

### 5. Working detection (selected seat)

| Mode | Source |
|------|--------|
| Team (presence snapshot on active session) | `MemberPresenceCubit` / presence map for `selectedMemberId` → `isWorking` |
| Personal / tabs that use shell activity | Same seat resolution as `MemberCoordination` / session working resolver for **that member only** |

Do **not** gate Stop on `ChatState.workingSessionIds.contains(sessionId)` alone.

### 6. Error / edge behavior

| Case | Behavior |
|------|----------|
| Shell offline / connecting | Send; Stop unavailable |
| `booting` / `idle` | Send |
| Permission UI while still `working` | Stop enabled; sends capability plan (Ctrl+C in v1) |
| Stop while still briefly `working` | Button stays Stop; further taps re-run plan |
| Switch selected member | Recompute from new member |
| History review with no connected shell | No Stop |
| Local PTY and SSH | Same `writeToPty` path |

## Testing

| Layer | Cases |
|-------|-------|
| Capability unit | Each built-in: `supportsTurnInterrupt` + `steps == ['\x03']` |
| `MemberTurnInterruptService` | Writes plan to fake PTY; cancels inject before write; no-op when disconnected / unsupported |
| Compose button logic / widget | working→Stop; idle→Send; unsupported→Send |
| Cubit (optional thin) | Forwards sessionId + memberId to service |

## Out of scope follow-ups (allowed by this design)

- Per-CLI Esc or Esc-then-Ctrl+C plans without UI changes
- Keyboard binding for Stop (command palette / Esc in compose focus)
- Team-wide “Stop all”
