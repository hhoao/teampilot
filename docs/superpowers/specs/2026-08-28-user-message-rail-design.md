# User-message rail — Design

**Date:** 2026-08-28
**Status:** Proposed
**Related:** [Context-aware find](2026-08-08-context-aware-find-design.md) (shared locate + highlight), [Chat history performance](2026-08-27-chat-history-performance-design.md) (`loadedMessages` / render window), [Failed message history](2026-08-27-failed-message-history-design.md) (optimistic user bubbles stay in the transcript).

## Problem

Long chat transcripts bury earlier user prompts. TeamPilot already has full-transcript find (`Mod+F`) and `ChatRevealController` jump+highlight, but there is no always-visible outline of **user turns**. Users cannot skim their own prompts and jump to one without searching.

Cursor-style interaction we are matching: a slim left timeline of user-message ticks; hover shows a preview card; click locates that bubble in the thread.

## Goals

1. Always-visible slim tick rail on the left of the session chat message area.
2. Hover a tick → preview card of that user message. Click tick or card → scroll to and highlight the bubble.
3. Locate is reliable: expand the history render window, **wait until the id is in the thread**, then reveal. Find and the rail share this locator.
4. Rail painting stays cheap at hundreds/thousands of user turns (one `CustomPaint`, one overlay card). Hover never rebuilds the thread.
5. Entry model and card footer are extensible (duration / git later) without rewriting the rail.

## Non-goals

- Work duration (“已工作 …”) and git commit chrome in v1 (footer slot exists, stays empty).
- Assistant-turn ticks, tool-call outline, or a minimap mapped to document height.
- Locating into the terminal PTY.
- Opening the rail by a toolbar button or a dedicated shortcut (rail is always on when it has entries). Keyboard applies **after the rail is focused**.
- Markdown in the preview card.
- A new cubit, a global bus, or a `shared_ui` primitive until a second consumer exists.

## Decisions (locked)

1. **Compact directory rail, not viewport-aligned markers.** Ticks are evenly spaced (one per user message in `loadedMessages`), independent of bubble height. Oldest at top, newest at bottom.
2. **Current seat only.** The rail follows the selected member’s transcript, same as the thread.
3. **Reuse find’s locate path, then strengthen it.** `AiHistorySeat.revealMessage` + `ChatRevealController.reveal` + highlight ring. Locator waits for the id instead of a single post-frame gamble. Find switches to the same locator.
4. **One CustomPaint + hit-test, one preview overlay.** No per-tick widgets.
5. **Active tick follows the thread’s owning user turn** via a `ValueNotifier`, fed from `VirtualThreadViewport`’s existing `TurnVisibleRange` (a `ThreadTurn` already starts at each user message).
6. **Hide the rail** when history is not ready, there are zero user messages, or a subagent preview covers the thread.
7. **Chat-only UI** lives under `pages/chat/`. Index and locator are Dart (no Flutter) so they test without widgets.
8. **Identity-stable index.** Incremental append reuses unchanged `ChatOutlineEntry` instances, same spirit as conversation-timeline merge.
9. **Resolve locate by id, then index.** Transcript merge can shift indices; a missing id is a silent no-op.

## Architecture

```text
AiHistorySeat.loadedMessages
        │
        ▼
buildChatOutline(messages)  →  List<ChatOutlineEntry>
        │                         id, messageIndex, preview, kind, chrome
        ▼
SessionChatMessageArea Stack
  ├─ SessionHistoryReviewMessages (thread)
  │     VirtualThreadViewport.onVisibleRange
  │           → owning user-turn id ValueNotifier
  ├─ ChatOutlineRail  (CustomPaint ticks + overlay card)
  └─ ChatFindBar (unchanged chrome)

Click / Enter / tap
        │
        ▼
ChatMessageLocator.locate(id, index)
        │  revealMessage(index)
        │  wait until runtime.messages contains id
        ▼
ChatRevealController.reveal(id) + highlightMessageId
```

### Units

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `ChatOutlineEntry` + `buildChatOutline` | Pure index: user turns, preview text, optional chrome | `AiMessage` |
| `ChatMessageLocator` | Expand window, wait for id, reveal + highlight | `AiHistorySeat`, `ChatRevealController` |
| `VirtualThreadViewport.onVisibleRange` | Publish existing `TurnVisibleRange` (turn indices) | height cache / scroll |
| `SessionHistoryThread` visible-owner notifier | Map first visible turn → user-message id | outline ids, `ThreadTurn.id` |
| `ChatOutlineRail` | Paint ticks, hit-test, hover/focus card, emit locate | entries + active id + locator callback |
| `SessionChatView` / `SessionChatMessageArea` | Wire seat, locator, highlight, hide rules | existing chat host |

Do not add a cubit. Do not fold this into `ChatTranscriptFindController` (search ≠ outline).

### Outline model

```dart
enum ChatOutlineKind { userTurn }

class ChatOutlineChrome {
  const ChatOutlineChrome({this.worked, this.gitSha});
  final Duration? worked; // v1: always null
  final String? gitSha;   // v1: always null
}

class ChatOutlineEntry {
  const ChatOutlineEntry({
    required this.id,
    required this.messageIndex,
    required this.preview,
    this.kind = ChatOutlineKind.userTurn,
    this.chrome = const ChatOutlineChrome(),
  });
  final String id;
  final int messageIndex; // index into loadedMessages
  final String preview;
  final ChatOutlineKind kind;
  final ChatOutlineChrome chrome;
}
```

`buildChatOutline(List<AiMessage> all)`:

- Include every `AiRole.user` (CLI turns, mailbox-merged, optimistic pending/failed). Same ground truth as the thread.
- `preview`: concatenate `AiTextPart` text only, collapse whitespace, truncate to 160 characters. Empty → l10n placeholder (`chatUserMessageRailEmptyPreview`). Do **not** use `plainTextForCopy` (it injects tool labels).
- Incremental: if `all` is a prefix-preserving append of the previous list, reuse prefix entries; append new user turns only.

### Locator

`ChatMessageLocator` (owned by `SessionChatView`, used by find and the rail):

1. Look up `id` in `seat.loadedMessages`. If found, use that index (ignore a stale argument). If not found, silent return.
2. `seat.revealMessage(index)` so the render window includes it.
3. If `seat.runtime.messages` already contains `id`, reveal on the next frame (layout).
4. Otherwise subscribe to runtime/seat updates until `id` appears or **450ms** elapses. On timeout, do not call `reveal` (thread stays put).
5. `ChatRevealController.reveal(id)` and set the shared `highlightMessageId`.

Find’s `_navigateFindTo` becomes a call into this locator (`hit.messageId`, `hit.messageIndex`). Highlight is no longer find-owned; it is locate-owned (find and rail share it).

### Visible owner (active tick)

`ThreadTurn` already starts a new turn on each user message; `turn.id` is that user message id (unless the thread leads with an assistant-only turn).

`VirtualThreadViewport` grows an optional `ValueChanged<TurnVisibleRange>? onVisibleRange`, fired when `_syncVisibleRange` commits a new range (not on every scroll pixel if the turn range is unchanged).

`SessionHistoryThread` maps `turns[range.firstIndex].id` to an outline id:

- If that id is a user-turn entry → it is the active tick.
- If the leading turn is assistant-only → no active tick.
- Publish through a `ValueNotifier<String?>` so the rail repaints ticks **without** `setState` on the message list.

### Placement

Overlay on the **left edge of `SessionChatMessageArea`’s thread `Stack`**, not inside `SingleChildScrollView`. Does not cover compose. Find bar stays top-right. Task board stays top-right. When `top != null` (subagent preview), omit the rail.

Width ~16–20px. The rail sits above the thread in the `Stack` and **rejects** hit tests outside tick slop so the thread still receives selection/scroll. Between ticks, nearest-tick wins if the pointer is within ≥16px slop of a tick.

## Interaction

**Desktop**

- Hover tick → preview card to the right of that tick (plain text, max 4 lines, ellipsis). Pointer may move tick → card without dismiss. Leave rail+card → close.
- Click tick or card → locate; card closes; highlight remains until the next locate or seat change.
- Hovering a different tick retargets the card by **id**.
- If `loadedMessages` refreshes under an open card, keep the card iff that id still exists; else dismiss.
- Rail is focusable after click/hover. `ArrowUp` / `ArrowDown` move the preview; `Enter` locates; `Escape` dismisses preview and unfocuses (does not close find). Do not steal compose focus until the user interacts with the rail.

**Touch**

- Tap tick → locate immediately.
- Long-press tick → preview card; second tap on the card locates; tap elsewhere dismisses.

**Density**

- Minimum tick gap ~10px. Total rail height = `max(viewport, n * gap)`. If `n * gap` exceeds the message-area height, the rail scrolls independently (its own `Scrollable`), still CustomPaint of the visible tick window (paint only ticks in the rail viewport + 1 overscan).

**Keyboard vs find**

- `Mod+F` remains find. The rail has no global shortcut.

## Appearance

- Vertical track: `onSurfaceVariant` at low opacity.
- Default tick: short hairline.
- Hover / focus / active / just-located: slightly longer and higher contrast. Active (scroll-synced) and hover may coincide; hover wins visually while the pointer is down on a tick.
- Card: surface container, rounded corners, short shadow, `TpTextStyles` body, 4-line clamp. Footer builder: `Widget? Function(ChatOutlineEntry)` — v1 returns null.
- Zero user messages, history not `ready`, or subagent overlay: `SizedBox.shrink()`.

## Error handling

| Case | Behavior |
|------|----------|
| History loading / error / empty | No rail |
| Subagent preview open | No rail |
| Locate id missing after merge | Silent no-op |
| Render window never contains id (timeout) | No reveal, no toast |
| Seat / member change | Dismiss overlay, clear highlight, rebuild outline |
| Find and rail locate in succession | Last locate wins (shared highlight + reveal epoch) |
| Empty user text | Tick still exists; card shows l10n placeholder |

No user-facing error chrome for locate misses.

## Performance constraints

- Outline rebuild is O(user turns) on transcript identity change; prefix reuse avoids allocating unchanged entries.
- Rail `build()` does not walk messages; it receives the outline list + `ValueListenable<String?>` active id.
- Hover / active-tick changes paint the rail and overlay only.
- Preview is truncated plain text, never a markdown view.
- `onVisibleRange` fires when the **turn range** changes, not per scroll pixel.
- Do not put the rail inside the virtualized thread column (that would relayout on every tick hover).

## Files (expected)

| Path | Change |
|------|--------|
| `client/lib/pages/chat/chat_outline.dart` | Entry / chrome / `buildChatOutline` |
| `client/lib/pages/chat/chat_message_locator.dart` | Shared locate |
| `client/lib/pages/chat/chat_outline_rail.dart` | CustomPaint rail + overlay + focus |
| `client/lib/pages/chat/session_chat_view.dart` | Own locator; find + rail call it; shared highlight |
| `client/lib/pages/chat/session_chat_message_area.dart` | Stack rail; hide on subagent |
| `client/lib/pages/chat/session_history_thread.dart` | Visible-owner notifier |
| `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` | `onVisibleRange` |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Placeholder + semantics |
| tests next to each unit | See Testing |

Layering: route-only UI in `pages/chat/`; viewport callback in `ai_message_ui` because that package already owns `TurnVisibleRange`. Not `widgets/`, not `shared_ui`.

## Testing

**`chat_outline_test.dart` (pure)**

- Mixed roles → only user turns, `messageIndex` matches `loadedMessages`.
- Preview truncates, collapses whitespace, ignores non-text parts.
- Empty text → placeholder passed in (inject the string; don’t load l10n).
- Prefix-preserving append reuses the same entry instances for old turns.

**`chat_message_locator_test.dart`**

- Calls `revealMessage` then `reveal` after the id appears in a fake runtime.
- Id absent → no `reveal`.
- Stale index, id still present → uses the current index.
- Timeout → no `reveal`.

**`virtual_thread_viewport` (extend existing reveal tests)**

- Scrolling to another turn reports a new `TurnVisibleRange`.
- Unchanged turn range does not spam callbacks.

**`chat_outline_rail_test.dart` (widget)**

- No entries → nothing painted / not in tree.
- Click tick invokes locate with that id.
- Click card invokes locate.
- Desktop hover shows preview text.
- Active id notifier lengthens the matching tick.
- ArrowDown + Enter locates the next entry.
- Seat-style remount (new entry list without the hovered id) closes the overlay.

**`session_history_thread` / message-area (widget, thin)**

- Subagent overlay: rail not built.
- Locate of an out-of-window user message expands via `revealMessage` and lands the highlight ring (reuse find’s reveal coverage; add one rail-driven case).

## l10n

| Key | en | zh |
|-----|----|----|
| `chatUserMessageRailEmptyPreview` | Empty message | 空消息 |
| `chatUserMessageRailSemanticLabel` | User message {index} of {total} | 用户消息第 {index} 条，共 {total} 条 |

## Out of scope (later, enabled by this spec)

- Fill `ChatOutlineChrome.worked` / `gitSha` and the card footer.
- Additional `ChatOutlineKind` values (assistant, tool).
- Promoting the paint rail to `shared_ui` if a second surface wants ticks.
