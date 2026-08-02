# tp_markdown

Semantic GFM markdown for Flutter: **compile → style-free IR → kind-based layout**.

TeamPilot’s chat and file-preview surfaces share this package. Host apps supply
[`MarkdownTokens`](lib/src/tokens/markdown_tokens.dart) (theme mapping) and
optional [`MarkdownResolvers`](lib/src/registry/markdown_resolvers.dart) /
[`MarkdownStrings`](lib/src/strings.dart).

## Pipeline

```
markdown string
  → prepareStreamingMarkdown (optional)
  → package:markdown (GFM AST)
  → compileMarkdown → MarkdownDocument (LRU-cached)
  → MarkdownView + gapBetween(prevKind, nextKind, tokens)  # collapse over marginOf; see 2026-08-02-markdown-block-margins-design.md
```

## Usage

```dart
final doc = compileMarkdown(source);
return MarkdownView(
  document: doc,
  tokens: myTokens, // host-built
  resolvers: MarkdownResolvers(onLinkTap: ...),
  strings: const MarkdownStrings(), // or localized
);
```

## Profiles

- `MarkdownProfile.document` — README / file preview spacing
- `MarkdownProfile.compact` — chat bubbles

Spacing is **never** inferred from `TextStyle`; only from [`MarkdownBlockKind`](lib/src/ir/markdown_block_kind.dart).

## Extensibility

- Override / extend [`BlockWidgetRegistry`](lib/src/registry/block_widget_registry.dart)
- Link + image hooks via `MarkdownResolvers`
- History collapse: [`truncateMarkdownDocument`](lib/src/compile/content_truncate.dart)

## Non-goals

WYSIWYG editing, KaTeX/Mermaid (extension points only), publishing yet (`publish_to: none`).
