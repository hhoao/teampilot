# History review: virtualized thread + lean message chrome

## Problem

Session history review (`SessionHistoryReview` → `AiThread`) scrolls poorly on long / heavy threads. A DevTools export (`test35.json`, debug build, 240 Hz) shows:

| Signal | Observation |
|--------|-------------|
| Bottleneck | **Build / layout**, not raster (raster ≈ 3.5 ms) |
| Worst frame | `#244352` **527 ms** build — **39×** `AiMessageView` + **39×** ActionBar `IconButton` + **44×** markdown `Text` in one frame |
| Scroll frames | `#244383` ~168 ms; hot path `RenderSliverList` / LAYOUT › BUILD |
| Chrome cost | ActionBar, tool/reasoning `Animated*`, `MarkdownBody` rebuild frequently while scrolling |

Today `AiThread` uses `ListView.builder` (lazy build within `cacheExtent`) plus sticky-bottom intent aligned with assistant-ui `useThreadViewportAutoScroll`, and `AiHistoryCubit` windows data (`kSessionHistoryInitialTurns` / load-older). That is not enough when each mounted row is markdown-heavy and chrome is always in the tree.

assistant-ui’s guidance: default `content-visibility` covers typical threads; for hundreds of messages or heavy per-message content, use **true virtualization** (`examples/with-virtualized-thread`: turn grouping, id-keyed rows, padding spacers, `measureElement`, self-owned sticky scroll).

## Goals

- Mount only turns near the viewport (+ overscan); represent the rest as spacer extent.
- Keep chronological (non-reverse) order, hide-until-stuck open, stick-to-bottom, scroll-to-bottom, and load-older scroll anchoring.
- Cut per-mounted-message build cost (ActionBar autohide, collapsed tool/reasoning, markdown parse cache).
- Preserve SelectionArea copy UX for **visible** content; accept that drag-select across unmounted turns is not guaranteed (same trade-off as aui virtualization).
- Prove wins with a before/after DevTools export on the same session scenario.

## Non-goals

- Changing history **IO** / parse pipeline (`AiHistoryLoader`) beyond keeping the existing data window as an optional upper bound.
- Streaming / live terminal history body (this is the non-running review surface).
- Cross-unmounted-message selection spanning.
- Porting `@tanstack/react-virtual` literally; match its **model**, implement in Flutter idioms.
- Profile-mode-only work; debug traces are valid for hotspot direction.

## Decisions (locked)

| Choice | Decision |
|--------|----------|
| Strategy | Optimal architecture first: **turn virtualization + lean chrome** in one design (not “cheap wins then maybe virtualize”) |
| Virtual unit | **Turn** = user message + trailing assistant/system messages (aui `buildTurns`) |
| Row identity | Turn id = first message id in the turn; messages rendered by **id** |
| Spacer model | Document-flow list with **paddingTop / paddingBottom** (or equivalent sliver spacers) — not absolute-positioned rows |
| Scroll ownership | `AiThread` owns the scroll element + sticky intent; measurement updates must not fight stick-to-bottom (aui `scrollToFn` guard) |
| Height cache | `Map<String, double>` turnId → measured height; estimate default **200** until measured; invalidate on content identity change for that turn |
| Overscan | **3** turns above and below viewport (tunable constant) |
| Data window | Keep `AiHistoryCubit` initial/load-older window as IO bound; rendering must not mount the whole window |
| Package boundary | Work lives in `client/packages/ai_message_ui` (+ tests); `session_history_review.dart` stays a thin host |
| Third-party scroll lib | Prefer **in-package** virtual viewport; add a dependency only if it clearly reduces correctness risk for measure/anchor |

## Architecture

```
AiHistoryCubit ──windowed──► ExternalStoreAiThreadRuntime.messages
                                      │
                                      ▼
                                 AiThread
                    ┌─────────────────┴─────────────────┐
                    │  TurnIndex (id, messageIds[])     │
                    │  HeightCache                      │
                    │  VirtualViewport (range+overscan) │
                    │  StickyBottomController           │
                    └─────────────────┬─────────────────┘
                                      │
              paddingTop ──► [visible turns] ──► paddingBottom
                                      │
                         MessageById → AiMessageView
                         (RepaintBoundary, lean ActionBar,
                          collapsed parts, cached markdown)
```

### Turn index

Pure function over `List<AiMessage>`:

- Empty → no turns.
- Each `AiRole.user` starts a new turn with `id = message.id`, `messageIds = [id]`.
- Non-user messages append to the last turn’s `messageIds` (if no last turn, start a turn with that message).

Rebuild the turn list only when message **membership / roles / ids** change (content-only updates keep the same turn array identity when possible).

### Virtual viewport

Replace `ListView.builder` idle path with a scrollable whose children are:

1. Optional load-older header (unchanged sentinel).
2. Top spacer sized to sum of estimated/cached heights of turns before the window.
3. Mounted turn widgets for `[firstVisible - overscan, lastVisible + overscan]`.
4. Bottom spacer for remaining turns.

Each mounted turn:

- `Key` / identity = turn id.
- After layout, record height into `HeightCache` (post-frame or `SizeChangedLayoutNotifier` / measure callback).
- Renders its `messageIds` via existing `AiMessageView` (or a thin `MessageById` lookup on the runtime list).

Scroll position ↔ index: derive visible range from `ScrollPosition.pixels`, cumulative heights (cache + estimate), and viewport dimension. On cache miss use estimate so the scrollbar remains usable before first measure pass.

### Sticky bottom (self-owned)

Preserve current semantics (plant stick on idle open / become idle; release on user scroll-up with stable extent; re-stick while intent active and content grows; hide list until first stick; scroll-to-bottom button).

Virtualization-specific rules (from aui):

- While stick intent is active, **suppress** measurement-driven scroll corrections that would pull the viewport away from the bottom (equivalent of custom `scrollToFn` early-return).
- Resize / late markdown growth of the **last** turn: re-pin to bottom while stick intent is active.
- Load-older: release stick, restore pixels with `maxExtent` delta (existing `_restoreScrollAfterOlderLoad` pattern), then update spacers/cache for newly prepended turns (those turns start unmeasured → estimate until scrolled into view).

### Lean message chrome

| Area | Behavior |
|------|----------|
| ActionBar | When not visible (hover reveal + not last + not copied/exported), **do not build** `IconButton`s; keep a fixed-height placeholder if needed to avoid layout jump |
| Tool / reasoning | Collapsed: trigger row only; no `AnimatedSize` body; prefer non-animated chevron when closed. Expanded: animations allowed |
| Markdown | Cache parse / built subtree keyed by content (+ style sheet generation); miss → parse once |
| Paint isolation | `RepaintBoundary` around each mounted `AiMessageView` |
| User bubble | Prefer max-width constraint without `IntrinsicWidth` when it conflicts with stable height measurement; short messages may grow to content width via cheaper layout if measurable |

### Host / pagination

- `SessionHistoryReview` continues to pass `hasOlder` / `onLoadOlder` / builders into `AiThread`.
- `kSessionHistoryInitialTurns` / page size remain; they bound how much is in the runtime list, not how many widgets mount.
- No requirement to change `session_history_pagination.dart` unless profiling shows the data window itself forces excess work before paint (unlikely once virtualization lands).

## Error / edge cases

| Case | Expected |
|------|----------|
| Empty / loading / error | Unchanged status builders; no virtual viewport |
| Single short turn | Works; spacers zero; stick-to-bottom trivial |
| Turn height changes (expand tool) | Remeasure; adjust spacers / scroll correction; if stick active and turn is last, stay pinned |
| Message removed / id missing | Skip render (`null`); drop cache entry |
| Rapid load-older | Coalesce; never stick-fight; anchor restore once per successful prepend |
| Extremely tall single turn | Still mounted when visible; overscan neighbors may be few; accept one heavy turn cost |
| Selection drag across spacer | Selection may break at unmounted boundaries — accepted |

## Testing

| Layer | Coverage |
|-------|----------|
| Unit | `buildTurns` grouping; height cache estimate vs measured; visible range from pixels + cumulative heights |
| Widget | Idle thread mounts ≤ overscan×2+visible turns for a long fake list; load-older preserves anchor; stick open still ends at bottom; ActionBar hidden has no `IconButton`; collapsed tool has no expanded panel |
| Existing | Keep `ai_thread_test`, `selection_area_test` green; update expectations that assumed full `ListView` child counts |
| Perf | Re-export DevTools on the same session: worst build frame down; single-frame `AiMessageView` rebuild count ≈ visible+overscan, not ~30–40 |

## File touch map (expected)

| Path | Role |
|------|------|
| `client/packages/ai_message_ui/lib/src/ai_thread.dart` | Wire virtual viewport + sticky |
| `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` (new) | Turn window, spacers, measure |
| `client/packages/ai_message_ui/lib/src/thread_turns.dart` (new) | `buildTurns` + types |
| `client/packages/ai_message_ui/lib/src/message_action_bar.dart` | True unload when hidden |
| `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Collapsed lean tree |
| `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Collapsed lean tree |
| `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | Markdown cache |
| `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | RepaintBoundary; optional IntrinsicWidth fix |
| `client/packages/ai_message_ui/test/*` | New + updated tests |

## Success criteria

1. Opening a long history review no longer builds O(window) full message trees in one frame; mounted count tracks viewport + overscan.
2. Scrolling jank driven by `RenderSliverList` layout of dozens of markdown trees is gone or sharply reduced on the same workload as `test35.json`.
3. Sticky-bottom, load-older, scroll-to-bottom, copy/export, and collapse/expand still behave correctly.
4. Package tests pass under `cd client && flutter test packages/ai_message_ui`.
