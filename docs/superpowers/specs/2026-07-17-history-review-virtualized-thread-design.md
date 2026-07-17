# History review: turn virtualization (height cache + spacers)

**Status:** Approved direction (2026-07-17). Supersedes host wiring in [`2026-07-16-history-review-virtualized-thread-design.md`](2026-07-16-history-review-virtualized-thread-design.md); turn model, spacer strategy, and lean-chrome goals from that doc remain in force unless this document says otherwise.

## Problem

History review must scroll without jumps on long, variable-height threads, and must not pay O(window) build/layout every frame.

### Evidence (ablation, 2026-07-17)

| Approach | Mid-scroll `maxScrollExtent` | Open / rebuild cost |
|----------|------------------------------|---------------------|
| Flyer `ChatAnimatedList` / `ListView.builder` + real messages | Huge mirrored swings (e.g. ±21388) when tall rows enter/leave cache | Lower mount count |
| Flyer + fixed-height placeholders | Stable | N/A (not real UI) |
| `SingleChildScrollView` + `Column` (current) | Stable | Full-tree BUILD/LAYOUT spikes (profile: worst ~143 ms build on `SessionHistoryThread`) |

Root cause of jumps: **variable-height rows + lazy cache churn** change extent while flinging. Eager `Column` fixes correctness and is **not** the long-term performance architecture.

Profile snapshot (`dart_devtools_2026-07-17_15_11_00.868.json`, linux profile, 240 Hz): p50 ~7.3 ms / p95 ~12.6 ms (acceptable for steady scroll); spikes are **build-bound** on `SessionHistoryThread` → Column layout, not raster (~3.5 ms).

## Goals

- Mount only turns near the viewport (+ overscan); represent the rest as **spacer extent** backed by estimated/measured heights.
- No mid-scroll extent swing (no naive per-message `ListView.builder`).
- Preserve history host behavior: chronological order, stick-to-end, load-older pixel anchoring, ActionBar hover gate during scroll.
- Preserve SelectionArea copy for **visible** content; drag-select across unmounted turns is not guaranteed.
- Prove wins with before/after DevTools on the same long session (compare to Column baseline and earlier `test35.json` Flyer baseline).

## Non-goals

- Changing `AiHistoryLoader` / parse pipeline beyond the existing IO window.
- Streaming / live PTY history body.
- Cross-unmounted-turn selection.
- Replacing correctness with Column micro-opts alone (RepaintBoundary-only, etc.).
- Third-party virtualizer packages unless measure/anchor proves unsafe in-package.

## Decisions (locked)

| Choice | Decision |
|--------|----------|
| Strategy | **Phase 1:** turn virtualization + height cache + spacers (correctness + mount cap). **Phase 2 (same PR or immediate follow-up):** lean chrome. Do not ship Phase 1 without a plan task list for Phase 2 |
| Forbidden | Naive `ListView.builder` / Flyer path without spacer height cache — already falsified |
| Virtual unit | **Turn** = user message + trailing assistant/system (same `buildTurns` rules as 2026-07-16) |
| Row identity | Turn id = first message id; messages keyed by `AiMessage.id` |
| Spacer model | Document-flow: `paddingTop` + mounted turns + `paddingBottom` (or equivalent sliver spacers) |
| Host | **`SessionHistoryThread`** owns scroll controller, stick, load-older, hover gate, `SelectionArea`, and **thread chrome** (`Align` / horizontal padding / `threadMaxWidth`); embeds `VirtualThreadViewport` for turn mount window only |
| Package | Core math + viewport widgets live in **`ai_message_ui`**; app host stays thin |
| Height cache | `Map<turnId, double>`; default estimate **200**; invalidate when turn **content identity** changes — message id set in the turn **or** concatenated part payload / hash of those messages changes. Expand/collapse UI state is **not** content identity → **remeasure only** |
| Overscan | **3** turns above and below (tunable) |
| Data window | Keep `AiHistoryCubit` message window; virtualization must not mount the whole window. `kSessionHistoryInitialTurns` is a **message** count despite the name — do not treat it as turn count |
| Stick semantics (history) | Match current `SessionHistoryThread` (no hide-until-stuck, no scroll-to-bottom FAB required). While stick active: suppress measure-driven scroll corrections; re-pin last turn growth |
| Measure vs scroll | Never call `jumpTo` from a scroll **listener** in a way that re-enters the listener (prior freeze). Prefer post-frame / notification-driven corrections |

## Architecture

```
AiHistoryCubit ──windowed──► ExternalStoreAiThreadRuntime.messages
                                      │
                                      ▼
                          SessionHistoryThread (app)
                    stick / load-older / hover gate / SelectionArea
                                      │
                                      ▼
                    VirtualThreadViewport (ai_message_ui)
                    ┌─────────────────────────────────────┐
                    │  buildTurns → TurnIndex             │
                    │  TurnHeightCache                    │
                    │  visible range + overscan           │
                    └─────────────────────────────────────┘
                                      │
              paddingTop ──► [mounted turns] ──► paddingBottom
                                      │
                         AiMessageView (per message id)
```

### Turn index

Pure function over `List<AiMessage>`:

- Empty → no turns.
- Each `AiRole.user` starts a new turn with `id = message.id`, `messageIds = [id]`.
- Non-user messages append to the last turn (if none, start a turn with that message).

### Virtual viewport

Children of the scrollable:

1. Optional load-older header (existing spinner sentinel).
2. Top spacer = Σ heights of turns before the mount window (cache or estimate).
3. Mounted turns for `[firstVisible - overscan, lastVisible + overscan]`.
4. Bottom spacer for remaining turns.

Each mounted turn:

- `Key` = turn id.
- After layout, write measured height into the cache (`SizeChangedLayoutNotifier` / post-frame callback).
- Renders `messageIds` via `AiMessageView`.
- `AiActionBarReveal.always` only for the **thread-final** message id (not per turn).

Visible range from `ScrollPosition.pixels`, viewport height, and cumulative cached/estimated heights.

### Stick + load-older (host)

Keep current `SessionHistoryThread` rules:

- Stick on open / non-prepend runtime updates; release on user scroll-up or load-older.
- Load-older: snapshot `pixels`/`maxExtent` → call cubit → one frame → `jumpTo(pixels + Δmax)`.
- Prepended turns enter cache as **estimates** until measured.

While stick intent is active, measurement updates must not pull the viewport off the bottom.

### Lean message chrome (same initiative)

| Area | Behavior |
|------|----------|
| ActionBar | Do not build `IconButton`s when hidden; fixed-height placeholder if needed |
| Tool / reasoning | Collapsed = trigger only (no expanded body / no `AnimatedSize` when closed) |
| Markdown | Keep existing compile/cache path; no regress |
| Paint | `RepaintBoundary` on mounted `AiMessageView` (already present — keep) |

## Error / edge cases

| Case | Expected |
|------|----------|
| Empty / loading / error | Unchanged status UI; no viewport |
| Single short turn | Spacers zero; stick trivial |
| Expand tool / reasoning | Remeasure turn; adjust spacers; if stick + last turn, stay pinned |
| Rapid load-older | Coalesce; one anchor restore per successful prepend |
| Extremely tall single turn | Still fully mounted when visible; accept cost |
| Selection across spacer | May break — accepted |
| Cache miss | Use estimate so scrollbar thumb stays usable |

## Testing

| Layer | Coverage |
|-------|----------|
| Unit | `buildTurns`; height cache cumulative / visible range; estimate vs measured |
| Widget | Long fake list mounts ≤ visible + 2×overscan; load-older preserves anchor; stick ends at bottom; expand remounts height |
| Host | New/updated widget tests for `SessionHistoryThread`: hover gate, SelectionArea wrap, load-older anchor with virtual viewport (no existing host tests today) |
| Perf | Profile export: mounted `AiMessageView` count ≈ viewport+overscan; worst build ≪ Column 143 ms / Flyer 527 ms on comparable session |

## File touch map (expected)

| Path | Role |
|------|------|
| `ai_message_ui/.../thread_turns.dart` (new) | `ThreadTurn`, `buildTurns`, content identity |
| `ai_message_ui/.../turn_height_cache.dart` (new) | Estimate / measure / invalidate / range |
| `ai_message_ui/.../virtual_thread_viewport.dart` (new) | Spacers + mounted turns + measure |
| `client/lib/pages/chat/session_history_thread.dart` | Replace Column with `VirtualThreadViewport`; keep stick/load-older/hover |
| Lean chrome files under `ai_message_ui` | ActionBar / tool / reasoning as in 2026-07-16 |
| `ai_message_ui/test/*` | New unit + widget tests |

Optional later: wire the same viewport into package `AiThread` for parity; **not required** for history-review success.

## Success criteria

1. Mid-scroll: no unexplained large `maxScrollExtent` swings (Column-class stability).
2. Open / load-older / fling: mounted turns ≈ viewport + overscan, not full IO window.
3. Stick-to-end, load-older anchor, hover ActionBar gate, visible copy/export, expand/collapse remain correct.
4. `cd client && flutter test packages/ai_message_ui` (and any host tests) pass.
5. Profile before/after on the same long session shows lower worst-build and lower per-frame message mount count.
