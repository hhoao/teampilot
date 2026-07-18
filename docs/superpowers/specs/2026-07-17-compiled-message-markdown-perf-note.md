# Compiled message markdown — perf note (test44)

**Date:** 2026-07-17  
**Branch:** `feat/compiled-message-markdown`  
**Exports:** test41 → 09:53 → 10:17 → test42 → test43 → **test44** (`~/Downloads/test44.json`)

## Outcome

History fling chrome goals for this initiative are **met**. Remaining cost is content layout (`RenderSliverList` / `RenderParagraph`), not markdown parse or ActionBar Material chrome.

| Milestone | Worst frame | Notes |
|-----------|-------------|--------|
| Pre-compile (test41 era) | MarkdownBody / tables hot | Baseline |
| Post-compile (09:53) | ~100 ms | `RenderTable` still present |
| Row/Column tables + ActionBar port (10:17) | ~96 ms | `IconButton` still hot |
| Lite ActionBar (test42) | ~113 ms | No `IconButton`; LAYOUT dominates |
| Lazy ActionBar + cheap tool headers (test43) | ~150 ms (noisy) | ActionBar icons off rebuild board when idle |
| Scroll-suppress hover (test44) | **~67 ms** | Cleanest recording; no ActionBar GD storm |

## What shipped (architecture)

1. **Compile → IR → `CompiledTextPartView`** — GFM via `package:markdown`; tables are Column/Row/`Expanded` (no Flutter `Table`/`RenderTable`).
2. **ActionBar** — lite icons (no `IconButton`/`Tooltip`); lazy mount; Opacity toggle; delayed unmount; `actionBarHoverEnabled` gate.
3. **History host** — `SessionHistoryThread` suppresses hover on scroll start/update and resumes only on **ScrollEnd** (+ short idle); `MouseRegion` stays mounted (gate ignores enter) to avoid scrollbar jitter from remounting hit-targets mid-fling.
4. **Tool / reasoning / tool-group** — `GestureDetector` headers (no `InkWell` / `AnimatedScale` / hover-`setState`).

## Out of scope (next initiative if needed)

- Flyer `itemExtent` / estimated extent / cacheExtent tuning  
- Truncating or virtualizing within a single long message  
- SelectionArea disable-while-scrolling  

## Gate check vs design AC

| AC | test44 |
|----|--------|
| `MarkdownBody` out of top UI hot paths | Yes |
| ActionBar `IconButton` out of top paths | Yes (no `IconButton`) |
| Table path without `RenderTable` | Yes |
| Worst fling frame improved vs pre-chrome noise | Yes (~67 ms build-bound) |
