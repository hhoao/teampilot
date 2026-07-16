# Full-screen PTY wrap-aware needle matching

## Problem

Full-screen PTY automation (`FullscreenPtyAutomation`) confirms paste by locating a needle on the terminal mirror grid, then confirms CR by checking that the same needle is no longer at the anchor.

`locateFullscreenPromptNeedle` / `_matchesNeedleAt` only match **within a single row**. Long landing text (especially CJK) soft-wraps in Claude Code and similar TUIs, so a 40-char tail needle often spans two rows. The text is visible on screen, but the probe returns `pasteNotFound`, so Enter is never sent and retries loop forever.

## Goals

- Treat soft-wrapped staged input as one logical character stream for paste ACK and CR ACK.
- Keep `FullscreenPromptAnchor` as a start position only (no end-span API change).
- Preserve existing composer-window scoping (`composerPrefix` + slack).
- Unit-test the wrap rules without requiring a live Claude PTY.

## Non-goals

- Changing `PtyAutomationNeedle` length or head/tail strategy.
- Changing per-CLI `FullscreenCrAckStrategy` (e.g. Claude staying on `anchorCellClears`).
- Skipping leading spaces / indent on continuation rows (strict match).
- Matching across blank rows (empty rows break soft-wrap continuity).
- Reworking deliver/retry scheduling in `MemberPtyInjectService`.

## Decisions (locked)

| Choice | Decision |
|--------|----------|
| Scope | Paste locate **and** `isFullscreenPromptAtAnchor` share one wrap-aware matcher |
| Soft wrap | At end of a row’s readable cells (or `columns`), continue at `(row+1, 0)` without inserting `\n` |
| Hard gap | If the next row has no content cells before needing the next needle rune, fail (do not jump over blank rows) |
| Continuation indent | Do **not** skip leading spaces on the next row; spaces must match needle if present |
| Wide spacers | Unchanged: skip `_flagWideSpacer` cells as today |
| Anchor | Still `(row, startCol, needle)` at the match start; CR ACK re-runs wrap-aware match from that start |
| Needle policy | Unchanged (`PtyAutomationNeedle.forText`) |

## Architecture

```
PtyAutomationNeedle.forText(text)
        │
        ▼
locateFullscreenPromptNeedle(grid, needle)     // bottom-up start candidates
        │
        ▼
_matchesNeedleAtWrap(grid, row, col, runes)    // NEW shared primitive
        │
        ├── used by locate (paste ACK)
        └── used by isFullscreenPromptAtAnchor (CR ACK)
```

Only `client/lib/services/terminal/fullscreen_input_screen_probe.dart` changes matching behavior. Callers (`TerminalFullscreenPtyPort`, `FullscreenPtyAutomation`) stay the same.

### Wrap-aware match algorithm

Starting at `(row, startCol)`:

For each needle codepoint, on the current `(row, col)`:

1. Skip wide-spacer cells on the current row.
2. **Soft-wrap gate** (before comparing): if `col >= columns`, **or** every remaining cell on this row is padding (`0` or `0x20` / wide spacer) while more needle runes remain:
   - Advance to `row + 1`, `col = 0`.
   - If `row` is out of grid → fail.
   - If the new row has no non-space content cells and the next needle rune is not space → fail (do not stitch across blank rows).
   - Skip wide spacers at the new row start; then continue the same needle codepoint.
3. Compare `codepointAt(row, col)` to the needle rune; mismatch → fail.
4. Advance past the cell (and its trailing wide spacer) as today.

If every needle rune matches → success.

Locate stays bottom-up over the composer-scoped window: for each row from bottom, try each non-spacer start column with this matcher; first hit wins.

### CR ACK

`isFullscreenPromptAtAnchor` calls the same wrap-aware matcher from `anchor.row` / `anchor.startCol`. If the staged wrap is cleared or moved, the match fails → `anchorCellClears` treats submit as done. No new strategy required for this bug.

## Error / edge cases

| Case | Expected |
|------|----------|
| Needle entirely on one row | Same as today |
| Needle spans two soft-wrapped rows (Claude CJK landing) | Locate succeeds; CR match true until cleared |
| Blank row between fragments | No match across the gap |
| Continuation row leading spaces not in needle | No match (strict) |
| Stale transcript above composer slack | Still ignored via `composerPrefix` window |
| Claude leaves history text after CR | Out of scope; may need `composerMovesDown` later — do not fold into this change |

## Testing

Extend `client/test/services/terminal/fullscreen_input_screen_probe_test.dart`:

1. **Wrapped CJK tail** — two rows reconstructing the production failure shape (`❯ …同时评估` / `是否支持 LDAP/AD…`); needle = last 40 chars; locate finds start on first wrap row.
2. **Single-row regression** — existing CJK / wide-spacer tests still pass.
3. **`isAtAnchor` wrap** — true while both wrap rows hold the needle; false after clearing those cells.
4. **Blank row gap** — needle split across rows with an empty row between → null.
5. **Composer slack** — existing stale-transcript-above-composer test still passes.

No change required to automation unit tests unless a fake port assumes single-row-only matching.

## Implementation notes

- Prefer replacing `_matchesNeedleAt` in place (all callers get wrap) over a parallel API, so locate and CR cannot diverge.
- Keep `_findNeedleStartCol` as “try starts on this row”; wrap handles continuation onto later rows.
- Update the `FullscreenPromptAnchor` / locate doc comments to say the needle may occupy following rows.
