# Task Board (AI Agent Work Tracker)

**Date:** 2026-06-15
**Status:** approved

---

## 1. Problem

In mixed-mode teams (cross-CLI coordination via TeamBus), the leader enqueues `TeamTask`s and idle workers claim them (`pending` → `claimed` → `done`/`failed`/`cancelled`). Today this work-queue state is invisible in the UI — the only windows into it are `MemberPresenceCubit` (working/idle) and `MailboxCubit` (member-to-member messages). There is no way to see *what* tasks exist, who owns each, and what is stuck or done.

Users managing mixed teams need a live view of the task queue to understand team progress at a glance, without reading the terminal.

## 2. Scope

**In scope:** a read-only task board panel in the right tools switcher that mirrors the active mixed-mode team's `TeamBus` task queue.

**Out of scope (deliberate):**
- **No manual task editing.** Tasks are created by the leader agent via the `add_tasks` MCP tool; the board reflects, it does not author. Manual editing would require write paths, conflict resolution, and a different product (A/C from the brainstorm) — explicitly deferred.
- **No native-mode support.** `TeamTask` is mixed-mode-only by design (native Claude swarm reuses Claude's own native task table; `tab_team_bus_coordinator.dart:68-79` passes `taskQueue: null`). The board tab is shown only when a mixed-mode bus is active — identical to how `Mailbox` is gated (`right_tools_panel.dart:117-122`). No empty-state placeholder for native mode: a UI for data that semantically does not exist would be noise.
- **No parsing of CLI-private task tables** (e.g. Claude's native tasks). That is a separate, CLI-coupled effort.

## 3. Architecture

The board is a **read-only visualization layer** over TeamBus's existing task queue. It adds **zero new persistence** and **zero changes to the data layer** — every read API it needs already exists.

```
TaskQueue (in-memory authority, mixed-mode only)
    │ list({status})  ← synchronous, pure in-memory map scan, zero IO
    ▼
TeamBus.listTasks({status})        (team_bus.dart:675 — already exists)
    │
    ▼   polled every 1.5 s (isomorphic to MailboxCubit)
BoardCubit (new, read-only) ──emit──▶ BoardState
    │                                  │ columns: Map<BoardColumn, List<BoardCard>>
    ▼                                  │ counts
BoardPanel (new UI)  ◀── BlocBuilder
    │ attach()/detach() controls poll lifecycle
    └─ TeamConfig (resolves assignee memberId → display name)
```

### 3.1 Why polling, not a change stream

`TaskQueue` runs in a single Dart isolate; all mutations (`addTasks`, `claimNext`, `release`, `update`, `reclaimExpired`) are synchronous atomic map writes with no change-broadcast stream. Adding a `Stream<Change>` would invade this carefully pure in-memory model and couple the queue to UI concerns. The cost of polling instead is one synchronous in-memory `list()` call per 1.5 s — effectively free. This mirrors the proven `MailboxCubit` design (`mailbox_cubit.dart`, 1500 ms `Timer.periodic`). Polling is also gated by `attach()`/`detach()`: only active while the board tab is visible, so no idle cost.

### 3.2 Data flow

1. `BoardPanel.initState` → `context.read<BoardCubit>().attach()` (starts timer).
2. Each tick: `_activeBus()` → `bus.listTasks()` (synchronous) → bucket by status into `BoardState` → `emit`.
3. `BoardPanel` reads assignee display names from the `TeamConfig` passed in.
4. `BoardPanel.dispose` → `detach()` (stops timer, clears state).

`_activeBus` is `() => chatCubit.activeTab?.teamBus` — the same channel `MailboxCubit` uses (`app_shell.dart:578-579`).

## 4. Components

### 4.1 `BoardColumn` enum — `client/lib/models/board_column.dart` (new)

Maps `TaskStatus` to board lanes. `TaskStatus` has 5 values; the board collapses the 3 terminals into a single "Done" lane distinguished by color/icon, because separate lanes for done/failed/cancelled would scatter a small dataset across too many columns in a 320 px-wide panel.

| `BoardColumn` | Mapped `TaskStatus` | Meaning |
|---------------|---------------------|---------|
| `pending` | `pending` | Waiting to be claimed |
| `claimed` | `claimed` | A worker is on it |
| `done` | `done`, `failed`, `cancelled` | Terminal (per-task color/icon distinguishes outcome) |

Pure mapping functions:
- `BoardColumn forStatus(TaskStatus s)` — forward map.
- `List<TaskStatus> statusesFor(BoardColumn c)` — reverse (for filtering).

### 4.2 `BoardCard` — value view over `TeamTask` (new, lives in `board_cubit.dart`)

An immutable projection of `TeamTask` for display, emitted by `BoardCubit` each tick. Not a new domain model — derived per tick, never persisted:

```dart
class BoardCard extends Equatable {
  final String id;
  final int seq;
  final String title;
  final TaskStatus status;
  final String? assigneeId;      // raw memberId; BoardPanel resolves to name
  final BoardColumn column;
  // derived in BoardCubit from TeamTask; constructor private to cubit layer
}
```

Kept as a separate type (rather than the panel reading `TeamTask` directly) so the UI never depends on `TeamTask.brief`/`dependsOn`/timestamps it doesn't render, and so the bucketing (`column`) is computed once per tick rather than on every `build`.

### 4.3 `BoardState` + `BoardCubit` — `client/lib/cubits/board_cubit.dart` (new)

Near-clone of `MailboxCubit` (`mailbox_cubit.dart`). Differences from mailbox:
- `_tick()` calls **synchronous** `bus.listTasks()` (no `await`, no `_inFlight` re-entrancy guard needed for the fetch — but keep `isClosed`/`_attached` guards).
- Emits a `BoardState` with the task list bucketed into `Map<BoardColumn, List<BoardCard>>` + per-column counts, instead of a flat feed.

```dart
class BoardState extends Equatable {
  final Map<BoardColumn, List<BoardCard>> columns;
  final int total;
  const BoardState({this.columns = const {}, this.total = 0});
  // empty() factory for the no-bus / detached case
  @override
  List<Object?> get props => [columns, total];
}

class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    required TeamBus? Function() activeBus,
    Duration pollInterval = const Duration(milliseconds: 1500),
  });
  void attach();   // start timer (idempotent)
  void detach();   // stop timer, emit BoardState.empty()
  // _tick(): bus null → emit empty; else listTasks() → bucket → emit
}
```

### 4.4 `BoardPanel` — `client/lib/widgets/right_tools/board_panel.dart` (new)

`StatefulWidget` mirroring `mailbox_panel.dart`:
- `initState`: `_boardCubit = context.read<BoardCubit>()..attach()`.
- `dispose`: `_boardCubit.detach()`.
- Constructor: `BoardPanel({required TeamConfig team, required String cwd})` — `team` resolves `assigneeId` → member `name` (fallback to raw id) and provides member count context.

Layout (vertical, within the ~320 px right-tools column — too narrow for horizontal kanban swimlanes):

```
┌─────────────────────────────────────┐
│ ◐ Pending (3)                        │  ← column header: icon + count
│   #1  Implement login API            │  ← card: seq, title
│   #4  Write migration guide          │
│   #5  Review PR #42                  │
├─────────────────────────────────────┤
│ ● Claimed (2)                        │
│   #2  Refactor auth    › developer   │  ← assignee chip when present
│   #3  Fix flaky test   › reviewer    │
├─────────────────────────────────────┤
│ ✓ Done (4)                           │
│   #6  Setup CI          ✓            │  ← outcome icon (done/failed/cancelled)
│   #7  Dark mode         ✕            │
└─────────────────────────────────────┘
```

Each card: leading `#seq`, title (1–2 lines, ellipsized), trailing assignee chip (member display name) or outcome icon. `failed`/`cancelled` cards tint with `colorScheme.error` to stand out. Tap on a non-terminal card → `ChatCubit.openMemberTab` for its assignee (same as mailbox `_jumpTo`), so users can jump to the member working it. Terminal cards with no assignee: no tap target.

**Empty state** (bus active, no tasks yet): centered `l10n.boardEmpty` text — same pattern as `mailbox_panel.dart:60-65`.

### 4.5 Integration points

| Location | Change |
|----------|--------|
| `client/lib/app/app_shell.dart:578-579` | Construct `boardCubit = BoardCubit(activeBus: () => chatCubit.activeTab?.teamBus)` next to `mailboxCubit`. |
| `client/lib/main.dart:271-294` | Add `BlocProvider.value(value: shell.boardCubit)` next to the mailbox provider (L276). |
| `client/lib/main.dart` `_AppShutdownScope.dispose` | Add `unawaited(widget.boardCubit.close())` next to mailbox close (L91). |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Add a `ToolView` in the `views` list, gated exactly like mailbox (L212-219): `showBoard` = `!isPersonalProject && mixed-mode && mailbox-style active-bus check`. Icon `Icons.view_kanban_outlined`. Placed after mailbox. |

### 4.6 Visibility preference

Add `boardVisible` to `LayoutPreferences` so users can hide the board tab entirely (parity with `membersVisible`/`gitVisible`). Touches 4 places following the established pattern (see Affected files). The board view is added to `views` only when `preferences.boardVisible && showBoard`.

`showBoard` is computed exactly like `showMailbox` (`right_tools_panel.dart:117-122`): `!isPersonalProject && team != null && mailboxCubit != null && team.teamMode == TeamMode.mixed && chatCubit.activeTab?.teamBus != null`. Board reuses mailbox's existence conditions because both consume the same `TeamBus` and only exist in mixed mode.

## 5. Assignee resolution

`TeamTask.assignee` is a raw memberId (e.g. `team-lead`, `developer`). `BoardPanel` resolves it to a display name via the passed-in `TeamConfig`:

```dart
String _memberName(String id) {
  final m = team.members.cast<TeamMemberConfig?>().firstWhere(
        (m) => m?.id == id,
        orElse: () => null,
      );
  return m?.name ?? id;     // fallback to raw id if member vanished
}
```

(`firstWhere` cannot return a nullable directly; the `.cast<TeamMemberConfig?>()` + nullable-orElse pattern, or `package:collection`'s `firstWhereOrNull`, avoids the `StateError` that a plain `firstWhere` would throw when the member is gone.)

If no member matches (member removed from roster mid-session), show the raw id rather than crashing — the task still exists in the queue. This keeps the board robust against roster drift.

## 6. Affected files

### New files

| File | Purpose |
|------|---------|
| `client/lib/models/board_column.dart` | `BoardColumn` enum + `TaskStatus`↔`BoardColumn` mapping |
| `client/lib/cubits/board_cubit.dart` | `BoardState`, `BoardCard`, `BoardCubit` (read-only poll) |
| `client/lib/widgets/right_tools/board_panel.dart` | `BoardPanel` UI |

### Modified files

| File | Change |
|------|--------|
| `client/lib/app/app_shell.dart` | Construct `boardCubit` (L578 region) |
| `client/lib/main.dart` | `BlocProvider.value(boardCubit)` (L276 region) + `close()` in shutdown scope (L91 region) |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Add board `ToolView` gated like mailbox (L212 region) |
| `client/lib/models/layout_preferences.dart` | Add `boardVisible` field (constructor/fromJson/copyWith/toJson/`withAtLeastOneToolVisible`) |
| `client/lib/cubits/layout_cubit.dart` | Add `boardVisible` to `setRegionVisibility` |
| `client/lib/pages/config/layout_region_visibility_section.dart` | Add board visibility `Switch` row |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | `board`, `boardEmpty`, `boardPending`, `boardClaimed`, `boardDone`, `boardVisibilityHint` |
| `client/lib/l10n/app_localizations*.dart` | Regenerated by `flutter pub get` |
| `client/lib/widgets/warmup_glyphs.g.dart` | Regenerated by `dart run tool/gen_warmup_glyphs.dart` (per AGENTS.md l10n rule) |

## 7. Behavior matrix

| Scenario | Behavior |
|----------|----------|
| Mixed-mode team, tasks exist | Board tab visible; columns show tasks, polled every 1.5 s |
| Switch to board tab | `attach()` → immediate tick + periodic poll |
| Switch away from board tab | `detach()` → timer cancelled, state cleared |
| Native-mode team | Board tab **not shown** (same gate as mailbox) |
| Personal project | Board tab not shown (`!isPersonalProject`) |
| No active bus (no session tab) | Board tab not shown |
| Bus active, queue empty | Board shows empty-state text |
| Member claims a task | Pending → Claimed within 1.5 s |
| Member reports done/failed | Moves to Done column, colored by outcome |
| Assignee removed from roster | Card shows raw memberId (no crash) |
| Tap a claimed card | Opens that member's chat tab |

## 8. Testing

- **`BoardCubit` unit test** (`client/test/cubits/board_cubit_test.dart`): inject a fake `activeBus` returning a stub `TeamBus` (or a lightweight double exposing `listTasks`). Verify: empty when bus null; correct bucketing for a mix of statuses; `attach`/`detach` lifecycle; `total` count. No `AppStorage` needed (cubit touches no filesystem).
- **`BoardColumn` mapping test**: every `TaskStatus` maps to the expected column; round-trip.
- **`BoardPanel` widget test** (`client/test/widgets/board_panel_test.dart`): with a stubbed `BoardCubit` emitting a known `BoardState`, verify columns render, assignee chip shows resolved name, empty state shows when empty, tap on claimed card calls `openMemberTab`. Provide `BoardCubit` via `BlocProvider.value`.
- No integration tests required for the read-only path (no new IO or persistence).

## 9. Non-goals / future work

- **Manual task creation/editing** (brainstorm option A/C): would need write paths into `TaskQueue` + conflict handling. Separate spec.
- **Native-mode task visibility**: would require parsing CLI-private task tables. Separate spec per CLI.
- **Drag-to-reassign**: reassigning tasks touches `TaskQueue.claim/release` semantics; deferred.
- **Persistence of board UI state** (collapsed columns, filters): none in v1; data is ephemeral and re-derived each session.

## 10. Open questions

None — all architectural decisions resolved during brainstorming (mixed-mode gating per mailbox precedent; polling per mailbox precedent; 3-lane collapse for narrow panel; assignee fallback to raw id).
