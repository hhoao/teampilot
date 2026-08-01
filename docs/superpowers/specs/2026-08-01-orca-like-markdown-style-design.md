# Orca-like markdown typography & table chrome

**Date:** 2026-08-01  
**Status:** approved design (pending implementation)  
**Scope:** chat IR (`CompiledTextPartView`) + file markdown preview (`MarkdownBody` via `toMarkdownStyleSheet`) share one host style

## Problem

TeamPilot markdown (chat + IDE preview) reads denser than Orca: tighter line height,
smaller block gaps, table cells with muted full-surface fill and heavier padding
deficit. Users want the airy Orca document feel without abandoning TeamPilot brand
colors or glyph-warmup constraints.

## Decisions (locked)

| Choice | Decision |
|--------|----------|
| Surfaces | **Unified** — same `CompiledMarkdownStyle` for chat and preview |
| Fidelity | **Spacing + table chrome**; keep `colorScheme.primary` for links (no GitHub blue) |
| Approach | **Single-source token tuning** in host + package table fields (not a second stylesheet, not ad-hoc fontSizes) |
| Out of scope | Table header `uppercase` / zebra stripes; separate chat vs preview density; new warmup font sizes |

## Visual contract

- Body / blockquote `height`: **1.7** (from 1.65)
- `blockSpacing`: **28** (from 24); `listItemSpacing` stays **8**
- Headings stay on `TpTextStyles` ladder (`display` / `xl` / …); apply **height 1.3**; h1 **letterSpacing -0.02**
- `MarkdownStyleSheet` heading top padding: **16 / 12 / 8** for h1–h3 (fallback path only; IR path uses `blockSpacing` between merged blocks)
- Tables: white/transparent body, light header fill (`onSurface` ~4%), light grid, cell padding **14×8**
- `mutedSurface` remains for code blocks / non-table chrome — **not** full-table fill
- Links: underline + `scheme.primary` (unchanged brand)

## Architecture

```
buildAppCompiledMarkdownStyle(theme)   # client/lib/theme/app_markdown_style_sheet.dart
        │
        ▼
CompiledMarkdownStyle                  # packages/ai_message_ui
        ├── CompiledTextPartView / _CompiledTable
        └── toMarkdownStyleSheet()     # MarkdownBody fallback / file preview
```

Host sets typography + spacing + table tokens. Package consumes fields only — no
Orca-specific hardcoding inside renderers beyond reading style fields.

## Package API additions (`CompiledMarkdownStyle`)

Add (or replace hard-coded literals with) configurable table chrome:

| Field | Purpose | Host target |
|-------|---------|-------------|
| `tableCellsPadding` | Cell inset | `EdgeInsets.symmetric(horizontal: 14, vertical: 8)` |
| `tableHeadBackground` | Header row fill | `onSurface` @ ~4% alpha |
| `tableBodyBackground` | Body cell/row fill | transparent |
| (existing) `borderColor` | Grid | `outlineVariant` @ **0.45** alpha (from 0.55) |

New fields should default in the constructor / `CompiledMarkdownStyle.test()` to
today's hard-coded behavior (`12×6` padding, header `mutedSurface@0.85`,
transparent body) so unrelated call sites stay stable; only the host builder
opts into the airy targets above.

`toMarkdownStyleSheet()` and `_CompiledTable` **must** both use these fields so
chat IR and preview stay aligned.

## Host token changes (`buildAppCompiledMarkdownStyle`)

- `body` / `blockquote`: `mdRelaxed.copyWith(height: 1.7)`
- headings: existing size tokens + `height: 1.3`; h1 also `letterSpacing: -0.02`
- `blockSpacing: 28`, `listItemSpacing: 8` (default args / call sites)
- wire table fields above; do **not** introduce ad-hoc `fontSize`

## Testing

- Update `app_markdown_style_sheet_test` for height `1.7` and `blockSpacing` `28`
- Update `ai_message_ui` markdown sheet / table expectations for padding + head decoration
- Sync probes that hard-code old rhythm (e.g. `selection_list_gap_probe_test` height/`blockSpacing`) if they assert those values
- Warmup coverage: height/letterSpacing ignored by `shapeKey` — no `gen_warmup_glyphs` unless ARB/chars change; fail if any new uncovered fontSize appears

## Non-goals

- Pixel-perfect clone of Orca CSS (including `#0969da` links)
- Changing app chrome outside markdown (page background, editor chrome)
- SelectionArea / strut / Flutter patch work (already separate)

## Success criteria

Side-by-side with Orca on the same README: noticeably airier body and headings,
tables without heavy gray wash and with roomier cells, TeamPilot link color
preserved, chat and preview match each other.
