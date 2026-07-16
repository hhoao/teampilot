# Compiled message markdown — design

**Date:** 2026-07-17  
**Status:** ready-for-planning  
**Primary goal:** cut history / long-thread **build·layout** cost from markdown tables and deep `MarkdownBody` trees (see DevTools `test41.json`)  
**Secondary goal:** keep GFM chat fidelity; allow optional math adapters later without putting them on the default path

## Locked decisions

| Topic | Decision |
|-------|----------|
| Default renderer | **Compile → IR → cheap widgets**; not gpt_markdown as body renderer |
| gpt_markdown / math | Optional **lazy adapter** for `math` / rare blocks only; not v1 |
| Scroll-defer hydrate | **Out of v1.** Tables/code are always “lite”; no post-idle visual upgrade that changes extent under Flyer |
| Scope | **Global `AiTextPartView`** switches to compiled path (history + any `AiMessageView`). Streaming: full recompile of that text part on update in v1 (history is static-first; live chat accepts recompile cost until dirty-tail lands) |
| Parser | `package:markdown` with `ExtensionSet.gitHubFlavored` (parity with current `flutter_markdown_plus` default) |
| Selection | Parent `SelectionArea`; child text `selectable: false` (unchanged model) |

## Context

History uses Flyer `ChatAnimatedList` + `AiMessageView`. ActionBar hover isolation landed; test41 no longer ranks ActionBar/IconButton as a top UI hot path.

Remaining cost: `MarkdownBody`, GFM tables, reasoning header InkWell, tool-call `Flexible`, `RenderSliverList` layout of deep subtrees.

`MarkdownBodyCache` avoids some rebuilds but not layout cost of mounted tables.

## Architecture

```
markdown string
  → prepareStreamingMarkdown (fence repair, existing)
  → AiMessageContentCompiler (GFM AST → MessageContentDocument)
  → LRU cache by content hash (style-free IR)
  → CompiledTextPartView (Text.rich + lite code/table widgets)
  → AiTextPartView (public entry; thin wrapper)
```

### Compiler IR (`ContentBlock`)

**Must-compile in v1** (zero `unsupported` for these):

- Headings h1–h6  
- Paragraphs  
- Ordered / unordered lists (nested); task-list items → checkbox glyph + text runs (no interactive checkbox widget required)  
- Blockquote, thematic break  
- Fenced / indented code (language + raw text)  
- GFM tables → cells are **inline-run documents** (bold/italic/strike/code/links allowed); **no nested block** markdown in cells  
- Inline: emphasis, strong, strikethrough, inline code, links (url + title), plain text  

**Explicit unsupported (fallback slice → existing `MarkdownBody` for that slice only):**

- Images, raw HTML, footnotes, math/LaTeX, anything else not above  

**Fallback acceptance gate:** on a frozen fixture corpus under `ai_message_ui/test/fixtures/markdown_corpus/` (≥20 samples including real-ish history exports), **≥95% of fixtures** compile with **zero** `unsupported` blocks. CI fails if gate regresses.

### Renderer

| Block | Widget policy |
|-------|----------------|
| Textual | Prefer **merging adjacent text blocks** into as few `Text.rich` as practical for selection quality |
| Links | `TapGestureRecognizer` / equivalent; forward to `AiTextPartView.onTapLink` when provided |
| Code | Muted surface + monospace `Text` + existing copy affordance pattern; no highlighter in v1 |
| Table | Flutter `Table` with **fixed/flex column widths** (no `IntrinsicColumnWidth`); cell content = `Text.rich` from inline runs; `RepaintBoundary` optional for paint isolation only (not a layout fix) |

No scroll-time upgrade path in v1 (avoids Flyer item extent jumps).

### Reasoning / tool (same initiative, separate AC)

- Reasoning collapsed: keep body unmounted (already true); replace header **`InkWell` + `AnimatedScale`** with a cheaper hit target where possible.  
- Tool collapsed: remove **`Flexible`** from `mainAxisSize: min` rows (use non-flex layout).  
- Expanded bodies mount once; not re-created on unrelated sibling hover.

### Host / Flyer

- No Flyer API change required for v1.  
- `SessionHistoryThread` stays host; compiled views are drop-in under `AiMessageView`.  
- Do not remount messages on ActionBar hover (already guaranteed).

### Styling

Map `ThemeData` + `AiMessageTheme` → `CompiledMarkdownStyle` (`TextStyle`s, code surface, table border). Transitional fallback slices may still read `markdownStyleSheet`.

## Non-goals (v1)

- gpt_markdown as default body renderer  
- Scroll-deferred “full fidelity” table upgrade  
- Parse on a background isolate  
- Perfect HTML / image markdown  
- Changing Flyer list implementation  

## Success metrics (measurable)

Baseline: `/home/hhoa/Downloads/test41.json` (or re-export same session after this lands as `test42`).

```bash
cd client
dart run tool/analyze_performance_json.dart ~/Downloads/test4N.json --format summary
```

| Check | Pass bar |
|-------|----------|
| `MarkdownBody` in top UI hot paths on fling/hover frames | **Absent from top 5** UI self-time paths (fallback-only mounts allowed if not in top 5) |
| ActionBar › IconButton | Remains out of top 5 UI hot paths (no regression vs test41) |
| Table / markdown layout self-time | `RenderTable` / `MarkdownBody` combined self-time on precision frames **≤ 50%** of test41’s corresponding hot-path self-time (document numbers in the perf note) |
| Fixture gate | ≥95% zero-`unsupported` |
| Widget tests | headings, lists (incl. task), links+`onTapLink`, table (incl. bold cell), code, SelectionArea copy smoke |

## Risks

| Risk | Mitigation |
|------|------------|
| Visual drift | Corpus fixtures + widget tests vs current samples |
| High fallback rate | Gate + expand must-compile set before claiming success |
| Selection gaps at block boundaries | Merge text runs; test copy |
| Streaming recompile jank | Accepted in v1; dirty-tail is follow-up |

## Rollout

1. Compiler + IR + corpus gate tests  
2. `CompiledTextPartView` + switch `AiTextPartView`  
3. Reasoning/tool layout cheapening  
4. Perf re-export vs test41  
5. (Later) math adapter spike — separate plan  

## Alternatives rejected

- **gpt_markdown default** — feature-oriented; unproven for Flyer layout jank  
- **Heavier MarkdownBody cache only** — insufficient for mounted table layout  
- **Raster/screenshot cache of messages** — breaks selection/theme  
