# Markdown block margins (per-kind EdgeInsets + host width scale)

**Date:** 2026-08-02  
**Status:** design (approved in brainstorming)  
**Extends:** `2026-08-01-markdown-semantic-renderer-design.md`, `2026-08-02-tp-markdown-package-design.md`  
**Related:** `shared_ui` `TpScaledEdgeInsets` / `TpWidthScale` (`tp_width_scale.dart`); file-preview chrome insets in `file_editor_surface.dart`

## Problem

Inter-block rhythm today is a handful of **scalar** gaps (`h*TopSpacing`, `headingBottom`, `paragraphGap`, `blockGap`, `ruleGap`) combined by `gapBetween(prev, next)` priority rules. Headings expose per-level **top** but only a **shared** bottom; left/right are not part of the matrix (list/blockquote/code use ad-hoc internal padding). Product wants:

1. **Per `MarkdownBlockKind` four-sided margins** (`EdgeInsets`).
2. **Optional multi-breakpoint scaling** via sparse `TpScaledEdgeInsets` (often only `sm` + `xxl`; unused stops lerp) — not a mandatory five-tier table.
3. **CSS-like vertical margin collapse** between adjacent blocks.

## Goals

1. Replace scalar gap fields with **resolved** `EdgeInsets` per block kind on `MarkdownTokens`.
2. Vertical gap between blocks = `max(prev.bottom, next.top)` (collapse).
3. Horizontal margins applied as outer `Padding` on top-level (and nested-document) blocks when non-zero.
4. Host (app) owns width scaling with `TpScaledEdgeInsets`; `tp_markdown` stays free of `shared_ui`.
5. Default width for scale resolution = **window** width (`MediaQuery.sizeOf(context).width`); host may pass another width later without API churn inside the package.
6. Keep document chrome (`_markdownPadding`) and block-internal chrome (`listIndent`, code/table padding, `listItemGap`) as separate systems.

## Non-goals

- Adding `shared_ui` as a dependency of `tp_markdown`.
- Auto-switching on markdown **pane** width (content-box); window width is the v1 default.
- Promoting list-item spacing to four-sided block margins.
- Changing selection-height / strut / glyph-warmup behavior.
- Pixel-perfect GitHub / CSS engine parity beyond collapse of adjacent vertical margins.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Margin model | Per-kind `EdgeInsets` via `MarkdownTokens.marginOf(kind)` |
| Vertical join | CSS-like collapse: `max(prev.bottom, next.top)`; **accept** deltas vs old priority `gapBetween` |
| Public gap helper | Keep name `gapBetween`; implement as collapse over `marginOf` |
| First / last block | No leading/trailing `SizedBox` for document edges; outer inset stays host chrome |
| Horizontal | `Padding(left/right)` only when non-zero; default L/R `0` for most kinds |
| Breakpoints | Sparse `TpScaledEdgeInsets` / `TpScaledDouble` in **app** builder; optional anchors |
| Width source | Default window width; resolve in host before constructing tokens |
| Package boundary | Host resolves → package receives plain `EdgeInsets` |
| Profiles | `document` / `compact` = two anchor presets, same token schema |
| Internal chrome | Unchanged (`listItemGap`, `listIndent`, table/code paddings) |
| Block widgets | Must not add outer top/bottom margins that duplicate collapse gaps |

## Token shape

Remove from `MarkdownTokens`:

- `h1TopSpacing` … `h6TopSpacing`
- `headingBottom`
- `paragraphGap`
- `blockGap`
- `ruleGap`

Add:

- `EdgeInsets marginOf(MarkdownBlockKind kind)` (explicit fields or private map; public accessor only)

Keep:

- Typography / colors / `codeBlockRadius` / table chrome colors
- `tableCellsPadding` (cell chrome, not block margin)
- `listItemGap`, `listIndent`

`MarkdownTokens.test` accepts optional per-kind (or shared) margin overrides with sensible defaults for package tests.

### Relationship to old `gapBetween` (locked)

Pure per-kind margins + collapse **cannot** reproduce the old priority matrix whenever
`paragraphGap ≠ blockGap` or `headingBottom ≠ ruleGap` (document profile today:
16 vs 28, and 8 vs 28). Example: `heading→list` used `headingBottom` (8) while
`paragraph→list` used `blockGap` (28) — one static `list.top` cannot satisfy both.

**v1 accepts that visual delta.** Collapse is the source of truth. Do **not** keep
priority branches or pair-specific exceptions. Update tests to assert collapse, not
legacy priority. Document profile anchors should be chosen for reading rhythm under
collapse (often unify “after heading” and “after paragraph” bottoms so neighbors feel
even), not for bit-exact match to the old matrix.

Keep the public helper name `gapBetween` as a thin wrapper over
`max(marginOf(prev).bottom, marginOf(next).top)` so call sites (`MarkdownView`,
merged-paragraph strut) stay stable; behavior change is intentional.

### Suggested default migration (document profile)

Prefer **bottom-owned** vertical margins (top often 0) so collapse is easy to reason
about; tune bottoms so typical pairs read well under `max`:

| Kind | top | bottom | left/right |
|------|-----|--------|------------|
| `headingN` | 0 (first heading after chrome); or a small shared top if preferred | per-level former `hNTopSpacing` used as **incoming** space via **previous** block’s bottom when possible; else put former top on heading.top | 0 |
| `paragraph` | 0 | former `paragraphGap` | 0 |
| `list` / `blockquote` / `code` / `table` / `image` / `rawLiteral` | 0 | former `blockGap` (document) / compact equivalent | 0 |
| `horizontalRule` | 0 | former `ruleGap` | 0 |

Practical heading recipe under collapse: put former `hNTopSpacing` on `headingN.top`
and former `headingBottom` on `headingN.bottom`. Then `paragraph→heading` gap ≈
`max(paragraph.bottom, heading.top)` which may be larger than today’s heading-only
top — **accepted**. If product later wants tighter heading stacks, lower
`paragraph.bottom` or `heading.top` in anchors; do not reintroduce priority rules.

Compact profile: smaller bottoms / tops via its own `TpScaledEdgeInsets` anchors.
## Collapse + layout

```text
gap(prev, next) = max(marginOf(prev).bottom, marginOf(next).top)
```

`MarkdownView` assembly:

1. If `previous != null` and `gap > 0`, insert `SizedBox(height: gap)`.
2. Build block via registry.
3. If `margin.left` or `margin.right` ≠ 0, wrap with `Padding(left/right)`.
4. Do **not** put `margin.top` / `margin.bottom` on that `Padding` (vertical rhythm is only the collapsed `SizedBox`).

Nested documents (list items, blockquote children) reuse the same `marginOf` + collapse. Spacing **between list items** remains `listItemGap`.

### Merged paragraphs

Adjacent `ParagraphBlock`s may still merge into one `Text.rich`. Blank-line `\n\n` strut height must equal `gap(paragraph, paragraph) / body.fontSize` — same number as the `SizedBox` path for non-merged paragraph pairs.

## Host scaling

`buildAppMarkdownTokens(theme, profile, {required double width})`:

1. Define per-kind (or shared) `TpScaledEdgeInsets` anchors for the profile (sparse OK).
2. `forWidth(width)` → `EdgeInsets`.
3. Construct `MarkdownTokens` with those resolved margins.

Call sites (chat `AiMessageTheme`, file `MarkdownView`) pass `MediaQuery.sizeOf(context).width` unless a parent already measured another width and chooses to forward it.

**Division of responsibility:**

| Layer | Owns |
|-------|------|
| File-editor `_markdownPadding` | Preview surface chrome inset |
| `MarkdownTokens.marginOf` | Inter-block rhythm + optional per-block L/R |
| Widget internal padding | Code header, table cells, list indent, blockquote bar inset |

## Testing

**Package**

- Unit: collapse matrix (heading→paragraph, paragraph→heading, paragraph→paragraph, hr, code); first block gap 0. **Do not** assert old priority values (`headingBottom` vs `blockGap` asymmetries).
- Widget: `SizedBox` heights; merged-paragraph blank-line height; non-zero L/R → `Padding`.

**App**

- Same profile, `width` at `TpBreakpoints.sm` vs `xxl` changes resolved heading/paragraph margins per anchors (and mid-band lerp when two stops set).
- Update every `buildAppMarkdownTokens(theme, profile)` call site (style sheet tests, warmup coverage, preview pane tests, chat theme) to pass `width` (tests may use a fixed width such as `TpBreakpoints.md`).
- Warmup / typography tests unchanged in intent. Rebuild tokens on resize when the host `build` sees a new `MediaQuery` width (normal Flutter rebuild; no separate cache keyed only by profile).
- Comment at call sites: markdown v1 margins resolve against **window** width by design (unlike some `TpWidthScale` pane-width hosts).
## Migration

1. Land `marginOf` + new `gapBetween` (or rename to `collapsedMarginGap`) in `tp_markdown` with updated tests.
2. Update `buildAppMarkdownTokens` + call sites to pass `width`.
3. Update semantic-renderer / package design docs that still describe the scalar gap matrix.
4. Delete obsolete scalar fields once call sites compile.

## Out of scope follow-ups

- Content-width (`LayoutBuilder`) driven margins.
- Per-breakpoint typography (fontSize) scaling — only margins/gaps here unless a later spec says otherwise.
