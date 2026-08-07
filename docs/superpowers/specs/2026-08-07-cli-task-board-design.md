# Chat CLI task board + task-tool bubbles

## Problem

When a CLI agent (Claude Code / flashskyai) runs a task-driven workflow, it manages a list of tasks through `TaskCreate` / `TaskUpdate` tool calls and renders the current board in its own TUI. The TeamPilot chat thread has **no visibility into that state**:

1. **Task tool calls render as generic tool rows.** A `TaskCreate{...}` / `TaskUpdate{...}` appears as a generic collapsible "Used tool: TaskCreate" row with a raw JSON panel (`_LegacyToolTrigger` in `ai_message_ui`). The task subject and status transitions are buried in JSON.

2. **The task board is invisible.** There is no persistent surface that shows "all of the CLI's tasks and their current status." Users watching a long agent run can't see at a glance what's done, what's in flight, and what's pending — they'd have to read the raw transcript.

The CLI JSONL transcript already contains everything needed: `TaskCreate` and `TaskUpdate` arrive as `AiToolCallPart` with structured `args` and a correlated `result` (`claude_compatible_jsonl.dart` parses them). The gap is purely in **derivation + presentation**.

## Decision

Add a **task-board capability** to the chat view in two independent render surfaces, both derived from the transcript — never from CLI-specific text parsing:

1. **Persistent floating task panel** pinned to the **top-right** of the chat message area (modeled on `git-tool-panel-demo.html`): a collapsible 320 px card showing the board (header count `completed/total`, status icon + subject per task, "… +N" overflow), updated live as the transcript grows.

2. **Task-tool bubbles**: `TaskCreate` / `TaskUpdate` tool calls render as dedicated task cards (subject + status pill, expandable detail) instead of the generic tool row, via a small **name-keyed custom-bubble hook** added to `ai_message_ui` (additive — existing Edit/Shell/Subagent/file tool chrome is untouched).

Architecture principle: **pure reduction for state, lightweight presenter for memoization, additive hook for rendering.** Bubbles render from a single part and are self-contained; the panel renders from a whole-transcript reduction. Scope is **per-seat** (the selected member's `AiHistorySeat`), matching the tab-per-member chat model.

## Architecture

### 1. Domain layer — `client/lib/services/cli/tasks/cli_task_board.dart` (pure Dart)

```dart
enum CliTaskStatus { pending, inProgress, completed, cancelled, unknown }

class CliTask {
  final String? taskId;        // from TaskCreate result (or update placeholder)
  final String subject;
  final String description;
  final String activeForm;
  final CliTaskStatus status;
  final int seq;               // creation/update order for stable display
}

class CliTaskBoard {
  final List<CliTask> tasks;
  int get completedCount;
  int get totalCount;
}
```

`CliTaskBoard reduceCliTaskBoard(List<AiMessage> messages)` — a pure, deterministic reducer:

- Walk `messages` in order; for each **assistant** `AiToolCallPart`:
  - **`taskcreate`** (case-insensitive): read `args.subject` / `args.description` / `args.activeForm`; read the task id from the correlated `result` — either a Map (`result['taskId']` / `result['id']`) or the Claude Code string form `"Task #N created successfully: …"` (extract `N`). Append a task with `status = pending`. If no id is extractable, keep `taskId = null` and still append (displayable, just not updatable by id).
  - **`taskupdate`**: `TaskUpdate` is a generic "update task N" tool, so **only a `status` arg is a lifecycle transition** — dependency/metadata updates (e.g. `addBlockedBy`) are ignored. With `status` present: read `args.taskId` + `args.status`, map the status string (`pending` / `in_progress` / `completed` / `cancelled`, anything else → `unknown`), and update the matching task. **If the taskId is not found** (e.g. resume where the create call predates the transcript window), append a placeholder task keyed by that taskId with empty subject — the board never silently loses a status-bearing entry.
  - Ignore every other tool name.
- Non-task tool calls and user/system messages do not affect the board.

Pure function, no IO, no Flutter dependency — directly unit-testable with `flutter test`.

### 2. Data wiring — `client/lib/services/cli/tasks/cli_task_board_controller.dart`

`CliTaskBoardController extends ChangeNotifier`:

- Constructed with an `AiThreadRuntime` (`historySeat.runtime`). Subscribes to `runtime.changes`.
- **Memoizes on message-list identity**: re-derives the board only when `runtime.messages` instance changes (the runtime already reuses unchanged message instances via `_mergeReusingUnchanged` and only notifies when content actually changed — so a `changes` ping that leaves the list identical is a no-op). Otherwise re-notifies without re-deriving.
- Exposes `CliTaskBoard get board`.

Ownership: `_SessionChatViewState` creates one per seat (keyed to `_seat`), disposes it in `dispose()`, and recreates it when the seat changes (mirroring `_bindSeat`). The floating panel is driven by a `ListenableBuilder` on the controller — fully decoupled from the per-second voice `setState` rebuilds.

### 3. Floating task panel — `client/lib/pages/chat/session_cli_task_panel.dart`

- Rendered as a `Positioned(top: spacing.sm, right: spacing.sm)` child of the message-area `Stack` in `SessionChatView` (the same `Stack` that hosts the thread and the subagent preview overlay). Hidden when `board.totalCount == 0`.
- **Collapsed**: a compact pill anchored top-right that surfaces the task currently **in progress** (spinner + subject, ellipsized to ≤240 px); when nothing is in progress it falls back to the task-icon + count pill.
- **Expanded**: a ~320 px card styled after `git-tool-panel-demo.html`:
  - Header row: title "任务" + count `N/M` (completed/total), plus collapse/expand icon buttons.
  - Task rows: status icon + `subject` (ellipsis, up to 2 lines).
  - Overflow: cap visible rows (~6), trailing "… +N 更多" expander matching the CLI's "… +N pending".
- Status icons: `pending → Icons.radio_button_unchecked` (hollow circle), `inProgress →` small `CircularProgressIndicator`, `completed → Icons.check_circle_outline`, `cancelled → Icons.cancel_outlined`, `unknown → Icons.help_outline`.
- Collapsed/expanded state is local widget state (not persisted); card uses theme tokens (surface, surfaceContainerHighest, onSurfaceVariant) and a subtle shadow.

### 4. Task-tool bubbles + package hook

**Hook (`ai_message_ui`, additive):** `lib/src/tool_call_bubble_scope.dart`

```dart
typedef AiToolCallBubbleBuilder = Widget Function(BuildContext, AiToolCallPart);

class AiToolCallBubbleScope extends InheritedWidget {
  const AiToolCallBubbleScope({required this.builders, required super.child});
  final Map<String, AiToolCallBubbleBuilder> builders; // keyed by lowercase tool name
  static AiToolCallBubbleScope? maybeOf(BuildContext context);
}
```

`AiToolCallPartView.build` consults the scope first: if `builders[part.toolName.toLowerCase()]` matches, wrap the returned widget in `SelectionContainer.disabled` and short-circuit **before** any generic chrome (subagent / shell / edit / file / legacy trigger). A missing scope or unmatched name falls through to today's behavior exactly. `AiToolGroupView`'s single-tool path routes through the same part view, so single task calls in a burst get the bubble too.

**Bubbles — `client/lib/pages/chat/cli_task_bubbles.dart`:**
- `CliTaskCreateBubble`: leading add icon, "TaskCreate" label, **subject** emphasized, status pill (`pending`), expandable detail showing `description` / `activeForm` / `result`.
- `CliTaskUpdateBubble`: task id + **status-transition pill** (e.g. `T9 → 进行中`), expandable detail showing raw args/result.
- Both reuse existing tool-card theme tokens (`markdown.toolTrigger`, `resolveToolPanel`, `panelRadius`, `partSpacing`) for visual consistency with the rest of the thread.

**Registration:** `SessionChatView` wraps the thread subtree in `AiToolCallBubbleScope(builders: { 'taskcreate': …, 'taskupdate': … })` (place above `SessionHistoryReviewMessages`).

### 5. Integration points

| Change | File |
|--------|------|
| Domain reducer + model | `client/lib/services/cli/tasks/cli_task_board.dart` (new) |
| Memoizing presenter | `client/lib/services/cli/tasks/cli_task_board_controller.dart` (new) |
| Floating panel widget | `client/lib/pages/chat/session_cli_task_panel.dart` (new) |
| Task bubbles | `client/lib/pages/chat/cli_task_bubbles.dart` (new) |
| Bubble hook | `client/packages/ai_message_ui/lib/src/tool_call_bubble_scope.dart` (new) + consult in `tool_call_part_view.dart` |
| Wire panel + scope into chat | `client/lib/pages/chat/session_chat_view.dart` |

## Error handling / edge cases

- **TaskUpdate before/without TaskCreate in the transcript window** → placeholder task with the given taskId (empty subject). Never crashes, never loses an entry.
- **TaskCreate result missing a taskId** → task is displayable; a later update by id can't reach it (id-less) — accepted limitation, no special handling.
- **Unknown status string** → `CliTaskStatus.unknown`, rendered with a neutral icon.
- **Huge transcripts** → derivation memoized on message-list identity; only one O(n) pass per actual content change.
- **Team vs simple mode** → per-seat panel means each member tab shows its own board; simple sessions show the single seat's board. No cross-member aggregation in v1.

## Testing

- **Reducer unit tests** (`test/services/cli/tasks/cli_task_board_test.dart`): create → pending entry; create+update → status flip; update-before-create → placeholder; status mapping incl. unknown; ordering by seq; non-task tools ignored; case-insensitivity.
- **Controller unit tests**: memoization (no re-derive when message list identical), re-derive on content change.
- **Panel widget tests**: header count `N/M`, status icons per status, collapse/expand, overflow "+N", hidden when empty.
- **Bubble widget tests**: TaskCreate shows subject + pending pill; TaskUpdate shows taskId + transition; unmatched tool names still render generic row.

## Future work (explicitly out of v1)

- Cross-member aggregation (feed multiple `AiThreadRuntime`s into one board).
- Additional task tools in the reducer (TaskGet / TaskList / TaskDelete) and bubble registry.
- Task interaction: click a task to locate it in the transcript; expand from panel into the thread.
- Board persistence across sessions.
