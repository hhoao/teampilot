# Render raw HTML blocks in markdown

## Problem

`tp_markdown` deliberately does not render HTML. Any region containing raw
HTML (a top-level `<details>` block, a paragraph with `<u>` / `<sub>` /
`<kbd>`, …) compiles to `RawLiteralBlock` and renders as monospace source text
(`content_compiler.dart` `_looksLikeHtml` / `_hasUnsupportedInline` →
`image_raw_blocks.dart` `buildRawLiteralBlock`). AI agent output and vendored
READMEs commonly embed such tags, so users see unrendered markup in chat
messages (`ai_message_ui` `text_part_view.dart`) and in the workbench markdown
preview pane (`VirtualMarkdownView`).

## Decision

Support arbitrary HTML by adding an `HtmlBlock` IR node rendered with
**flutter_html inside `tp_markdown`** (chosen over app-side registration via a
builder hook, and over `flutter_widget_from_html_core`). The built-in
`BlockWidgetRegistry.builtIn()` registers an `HtmlBlock` builder, so all
existing `MarkdownView` / `VirtualMarkdownView` construction sites pick it up
with zero call-site changes. Styles are derived from `MarkdownTokens`, so HTML
blends into the surrounding Tp-themed markdown typography.

Scope:

- **Both consumers**: chat AI messages and the markdown file preview (both go
  through `tp_markdown`).
- **Arbitrary tags**, subject to sanitization (below). Not a tag whitelist.
- **Theme-integrated styling**, not browser-default look.
- Known trade-off accepted: GFM syntax *inside* a demoted HTML region is not
  parsed (the html engine does not speak markdown). This is still strictly
  better than today's behavior for those regions (rendered vs raw text).

### Compile rule: only non-GFM-injecting demotion paths become HtmlBlock

flutter_html cannot parse reconstructed GFM, so demotion paths that rebuild
markdown syntax keep `RawLiteralBlock`:

| Existing path | Becomes | Why |
|---|---|---|
| Top-level bare HTML text (`_looksLikeHtml`) | `HtmlBlock` | Already raw HTML |
| `<p>` with unsupported inline tag (`_reconstructUnsupported(p)` = plain child concatenation) | `HtmlBlock` | Tags preserved verbatim |
| List-item inline demotion (same concatenation shape) | `HtmlBlock` | Same |
| Table demotion (rebuild injects `\| --- \|` GFM row) | stays `RawLiteralBlock` | html engine would paint the table as literal text |
| Heading demotion (rebuild injects `#` prefix) | stays `RawLiteralBlock` | Same reasoning |

Task-list `<input type=checkbox>` keeps its existing exemption (never counts as
unsupported HTML).

## Components

### IR (`packages/tp_markdown/lib/src/ir/`)

- `final class HtmlBlock extends MarkdownBlock { final String rawHtml; }`
- `MarkdownBlockKind.html` added to the enum.

### Compiler (`content_compiler.dart`)

Route the paths marked `HtmlBlock` in the table above to
`HtmlBlock(rawHtml: ...)`; leave the two GFM-injecting rows untouched. No
inline-level
changes (unknown inline wrappers already trigger paragraph-level demotion
before `_compileInlineNode` sees them).

### Renderer (`lib/src/render/html_block.dart`, new)

`Widget buildHtmlBlock(HtmlBlock block, MarkdownTokens tokens,
MarkdownResolvers resolvers)`:

- **Sanitize before rendering** (defense in depth; flutter_html executes no
  JS): strip `script` / `iframe` / `object` / `embed` elements, `on*` event
  handler attributes, and `javascript:` URLs.
- **Style mapping** from `MarkdownTokens`: body fontSize / color / height /
  fontFamily → body style; link color, code background, h1–h6 size scale,
  blockquote indent, table borders from the existing token API so the block
  matches surrounding markdown spacing and theme (light + dark).
- **Wiring**: link taps → `MarkdownResolvers.onLinkTap`; images resolved via
  `MarkdownResolvers.resolveImage` (reuses the workspace image pipeline);
  unresolved images fall back to the existing placeholder.
- **Fallbacks**: parse exception → render via `buildRawLiteralBlock`
  (original source, never crash); sanitized-empty content →
  `SizedBox.shrink()`.

Registered in `BlockWidgetRegistry.builtIn()`. `tp_markdown/pubspec.yaml`
gains `flutter_html`.

## Adjacent adaptations

| Site | Change |
|---|---|
| Search index (`markdown_search_index.dart` skip branch) | `HtmlBlock` contributes its **plain text** (via the html parser's `.text`) as a search container so preview find hits HTML content |
| Truncation estimate (`content_truncate.dart` `_estimateBlockChars`) | `rawHtml.length` (same accounting as `RawLiteralBlock`) |
| Block gaps / margins (`gapBetween` / `marginOf`) | `html` kind grouped with paragraph spacing |
| Streaming chat | No special handling: incremental recompilation already flows through the LRU doc cache; unclosed mid-stream tags render best-effort via the tolerant parser |
| `VirtualMarkdownView` height measurement | No change expected: arbitrary-widget units already measured (same path as `SelectableText` in `RawLiteralBlock`) |

## Error handling

Parse exceptions and empty-sanitized content degrade as described above;
dangerous elements never reach the renderer. No new failure surfaces beyond
fallback-to-source-text.

## Testing

Package tests under `client/packages/tp_markdown/test/`:

- Compile: each of the five paths produces the intended IR type; task-list
  checkboxes still exempt; mixed `**bold**` + `<u>` paragraphs compile to one
  `HtmlBlock`.
- Sanitizer: script/iframe/on* attributes/javascript: URLs removed; benign
  markup preserved.
- Widget tests: `<b>/<u>/<sub>` produce styled spans; link tap fires
  `onLinkTap`; images go through `resolveImage`; parse failure falls back to
  source text.
- Search index includes `HtmlBlock` plain text; truncate estimate branch.

Project gate before done: `cd client && flutter analyze --no-fatal-infos
--no-fatal-warnings && dart run tool/run_tests.dart`.

Out of scope: interactive HTML (collapsible `<details>` interaction, form
controls), CSS `<style>` blocks, per-tag user configuration, HTML inside code
blocks (already literal), GFM reconstruction inside html regions.
