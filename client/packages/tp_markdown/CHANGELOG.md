# Changelog

## 0.2.0

- Raw HTML regions compile to HtmlBlock and render via flutter_html (sanitized;
  styles derive from MarkdownTokens). Tables/headings containing raw HTML still
  render as source text.
- Search indexing includes HtmlBlock plain text.

## 0.1.0

- Initial extract from `ai_message_ui`: IR, compile (+ LRU cache), tokens,
  `MarkdownView`, registries, streaming prep, history truncate.
