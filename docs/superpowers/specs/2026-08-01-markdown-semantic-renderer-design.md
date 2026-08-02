# Semantic markdown renderer (single IR path)

**Date:** 2026-08-01  
**Status:** design (locked by product owner: best architecture / extensibility; no backward compat)  
**Supersedes (layout architecture):** dual-path spacing / `toMarkdownStyleSheet` as the preview authority in `2026-08-01-orca-like-markdown-style-design.md`  
**Keeps (visual targets):** Orca-like body height 1.7, heading scale, table chrome, `colorScheme.primary` links from that spec — re-homed onto profile tokens below.

## Problem

TeamPilot already has a style-free IR for chat (`ContentBlock` + `CompiledTextPartView`), but file preview and IR fallbacks still go through `flutter_markdown_plus` `MarkdownBuilder`. Spacing there is driven by widget shape and **style-fingerprint heuristics** (`_spanLooksLikeHeading`). That caused real bugs (e.g. `h6 == body` → every paragraph treated as a heading → paragraph gaps collapsed) and guarantees chat/preview drift.

Token tuning alone cannot fix a dual layout engine.

## Goals

1. **One compile → one semantic document → one renderer** for chat and file markdown preview.
2. **Structure never inferred from TextStyle** — only from block / inline kinds produced by the compiler.
3. **Spacing is a pure function of `(prevKind, nextKind, profile)`** via `marginOf` + collapse — no padding+blockSpacing double-counting, no merge-time special cases that disagree with Column gaps.
4. **Extensible** via registries (compile transforms, block widgets, link/image resolvers) without forking the builder.
5. **Two presentation profiles** (`document`, `compact`) sharing IR + token schema (Orca preview vs comment pattern).
6. **No backward compatibility** with `MarkdownStyleSheet` layout APIs, `_spanLooksLikeHeading`, or product use of `MarkdownBody` for GFM document bodies.

## Non-goals

- WYSIWYG / round-trip rich editing (follow-up project; share tokens + block kinds later).
- Pixel-perfect GitHub CSS or Orca’s KaTeX/Mermaid in v1 (extension points yes; ship math/mermaid only if registry plugins land in the same effort’s plan).
- Preserving `flutter_markdown_plus` as a layout engine.
- Keeping `UnsupportedBlock → MarkdownBody` as a normal path for common GFM.

## Decisions (locked)

| Topic | Decision |
|-------|----------|
| Approach | Semantic IR path (initially in `ai_message_ui`; **extracted** to `tp_markdown` — see `2026-08-02-tp-markdown-package-design.md`) |
| Surfaces | Chat + file preview both call the same renderer |
| Profiles | `MarkdownProfile.document` (preview / README) and `.compact` (chat) |
| Spacing | Per-kind `marginOf` + CSS-like collapse via `gapBetween` (see `2026-08-02-markdown-block-margins-design.md`); block widgets do not add competing outer margins |
| Selection | Keep `SelectionArea` + strut / line-spaced selection style; merge only adjacent **paragraph** runs when safe for selection continuity, using the **same** gap matrix for blank-line advance |
| Preview chrome | Code copy button, tables, images, task lists live in IR widgets (parity with document profile needs) |
| Unknown HTML / exotic nodes | `RawLiteralBlock` showing source (or sanitized subset via plugin) — never silent drop |
| `flutter_markdown_plus` | Remove from product markdown body paths; delete or gut layout fork once consumers migrate |
| Compat shims | None (`toMarkdownStyleSheet` deleted from product API) |

## Architecture

```
raw markdown string
        │
        ▼
┌───────────────────┐
│ MarkdownPipeline  │  prepare (streaming fence fix) → parse (GFM) →
│                   │  compile transforms (sanitize, resolve) → IR
└─────────┬─────────┘
          ▼
   MarkdownDocument { blocks: List<MarkdownBlock> }   # style-free, cacheable
          │
          │  + MarkdownTokens.forProfile(theme, profile)
          ▼
┌───────────────────┐
│ MarkdownView      │  gap(prev, next) → SizedBox / encoded blank line
│                   │  BlockRegistry.build(block, tokens, resolvers)
└───────────────────┘
          │
     ┌────┴────┐
     ▼         ▼
  chat       file preview
  compact    document
```

### Package layout (`client/packages/ai_message_ui`)

| Module | Responsibility |
|--------|----------------|
| `markdown/ir/` | Sealed `MarkdownBlock` / `InlineNode` (rename/evolve today’s `ContentBlock` / `InlineRun`) |
| `markdown/compile/` | `MarkdownPipeline.compile(source, {streaming, plugins})` |
| `markdown/tokens/` | `MarkdownTokens`, `MarkdownProfile`, `gapBetween(prev, next)` |
| `markdown/render/` | `MarkdownView` + built-in block widgets |
| `markdown/registry/` | `BlockCompilerPlugin`, `BlockWidgetBuilder`, `MarkdownResolvers` (links, images) |

Host (`client/lib/theme/…`): only builds `MarkdownTokens` from `TpTextStyles` / `TpFontTheme` / `ColorScheme` for each profile. No layout logic.

Consumers:

- `AiTextPartView` → pipeline + `MarkdownView(profile: compact)`; preserve history IR truncation (`content_truncate` / expandable history) before render.
- `_MarkdownPreviewPane` → pipeline + `MarkdownView(profile: document)` + preview resolvers (workspace-relative links/images); keep `SelectionArea` **inside** the scrollable content (avoid jump-to-top on long docs).

### Rename policy

Prefer clear names in the new surface (`MarkdownDocument`, `MarkdownView`, `MarkdownTokens`). Migrate call sites in-repo; do not keep dual names long-term. Old `CompiledMarkdownStyle` / `CompiledTextPartView` / `toMarkdownStyleSheet` names go away with the migration.

## Block model

Style-free sealed hierarchy (evolve existing IR):

**Blocks:** `Paragraph`, `Heading(level 1–6)`, `List(ordered, items)`, `ListItem(runs, children, taskChecked?)`, `Blockquote(children)`, `Code(language?, text)`, `Table(rows)`, `HorizontalRule`, `Image(src, alt?)`, `RawLiteral(source)`  

**Inlines:** `Text`, `Strong`, `Emphasis`, `Strikethrough`, `Code`, `Link(href)`, `Image` (inline), plus plugin-defined nodes via a small `CustomInline` escape if needed.

Compiler maps `package:markdown` GFM AST tags → these kinds. No widget construction at compile time.

### Images & HTML

- **Images:** first-class `Image` block/inline; `MarkdownResolvers.resolveImage` supplies bytes/provider (local workspace, http policy).
- **HTML:** default strip/unknown → `RawLiteral`. Optional `HtmlAllowlistPlugin` may promote a tiny safe subset (`br`, simple anchors) into IR. No unsanitized HTML widgets.

## Spacing model

See **`2026-08-02-markdown-block-margins-design.md`** for the locked margin-collapse spec.

### Kind enum

```dart
enum MarkdownBlockKind {
  paragraph,
  heading1, heading2, heading3, heading4, heading5, heading6,
  list,
  blockquote,
  code,
  table,
  horizontalRule,
  image,
  rawLiteral,
}
```

Each `MarkdownBlock` exposes `.kind`. Nested containers (`blockquote`, `list` items) render child documents with the **same** `gapBetween` + tokens — no second spacing system inside nests.

### Gap function

```dart
EdgeInsets marginOf(MarkdownBlockKind kind);
double gapBetween(MarkdownBlockKind? previous, MarkdownBlockKind next, MarkdownTokens t);
```

`gapBetween` = CSS-like vertical collapse: `max(prev.bottom, next.top)` over `marginOf` (no scalar priority matrix). First block in a document/container has no leading `SizedBox`; host chrome owns outer inset.

List **items** use `t.listItemGap` inside the list widget (not `gapBetween` between top-level blocks).

Document profile mirrors Orca `markdown-preview.css` intent (heading ~1.5em/0.5em, paragraph ~0.75em, list/code/table ~0.75–1em). Per-kind margin anchors for both profiles live in the margins spec + host `buildAppMarkdownTokens`.

**Invariant:** block widgets paint **internal** chrome only (code padding, table cell padding, blockquote bar). They must not add outer top/bottom margins that duplicate `gapBetween`.

**Selection merge:** only adjacent `Paragraph` blocks may merge into one `Text.rich`. Blank-line advance uses `gapBetween(paragraph, paragraph)` encoded as `\n\n` height — **same number** as `SizedBox` path. Headings never merge (kind-based, not style-based).

Compact profile uses the same collapse function with smaller per-kind margins (chat density).

### Token fields (host-filled)

Typography: body, h1–h6, link, inlineCode, codeBlock, listBullet, blockquote, tableHead/Body (warmup-safe sizes only).

Chrome: `borderColor`, `mutedSurface`, `codeBlockRadius`, `tableCellsPadding`, `tableHeadBackground`, `tableBodyBackground`.

Rhythm: per-kind `marginOf` (four-sided `EdgeInsets`), `listItemGap`, `listIndent`, body/blockquote `height` 1.7 (document). Host resolves sparse `TpScaledEdgeInsets` to plain `EdgeInsets` before constructing tokens.

Visual numbers start from the approved Orca-like targets (body 1.7, heading tops ~40/36/32/…, heading bottom ~8, table 14×8, border alpha 0.45) and are adjusted per profile — not re-debated here. Do **not** separately execute the old dual-path token plan in `2026-08-01-orca-like-markdown-style` implementation plan; fold remaining visual targets into `MarkdownTokens` here.

## Extension model

1. **Compile plugins** — `(md.Node) → MarkdownBlock?` or document-level rewrite (frontmatter strip, doc-link rewrite).
2. **Block widget builders** — `Map<Type, Widget Function(block, tokens, resolvers)>`; built-ins registered by default; host/features can override `Code` / `Table`.
3. **Resolvers** — `onLinkTap`, `resolveImage`, optional path → workspace file open (preview).
4. **Profile** — choose token set only; plugins can be profile-gated (e.g. syntax highlight only on `document` later).

Future WYSIWYG should consume the same `MarkdownBlockKind` + `MarkdownTokens`, not invent a third spacing system.

## Migration

1. Introduce `MarkdownPipeline` / `MarkdownView` / `MarkdownTokens` alongside old names only during the implementation branch; land as replace, not long-lived alias.
2. Point file preview at `MarkdownView(document)`.
3. Point chat at `MarkdownView(compact)`.
4. Expand compiler so corpus / README fixtures compile without `RawLiteral` for standard GFM (images included).
5. Delete product use of `buildAppMarkdownStyleSheet`, `MarkdownBody` for document bodies, and layout heuristics in `flutter_markdown_plus`.
6. Remove or shrink the `flutter_markdown_plus` submodule dependency from `ai_message_ui` / app once unused.
7. Update selection / corpus / theme tests to assert **kind-based gaps** and profile tokens.

## Testing

- **Unit:** `gapBetween` collapse table (first block, heading→list, paragraph→paragraph, heading false-positive regression with h6==body tokens).
- **Compile corpus:** existing gate ≥95% without RawLiteral for must-compile fixtures; add README-like fixture used in preview.
- **Widget:** preview and chat both render the same fixture IR with different profiles; assert no `MarkdownBody` in the subtree for must-compile docs.
- **Selection:** list gap probes + paragraph merge still pass under strut / line-spaced selection.
- **Warmup:** no new ad-hoc fontSizes outside `TpTextStyles`.

## Risks

| Risk | Mitigation |
|------|------------|
| Preview feature gap (images) | First-class Image block + resolvers before cutting MarkdownBody |
| Large README perf | Keep compile LRU; memo document per source hash; profile-only rebuild on theme |
| Selection regressions when stopping heading merge heuristics | Kind-based merge rules + existing selection probes |
| Scope creep (math/mermaid) | Registry hooks only unless explicitly scheduled in the implementation plan |

## Success criteria

- One renderer path for chat + markdown file preview.
- Zero style-fingerprint heading detection in production code.
- Paragraph / heading / list spacing matches margin collapse; no “paragraph gaps vanished” class of bugs.
- Adding a new block type = compile mapping + widget builder + gap row — not a fork of `builder.dart`.
