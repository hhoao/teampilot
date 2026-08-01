# Extract `tp_markdown` package

**Date:** 2026-08-02  
**Status:** design (approved: extract path package; best architecture / extensibility / performance)  
**Supersedes (packaging):** “evolve inside `ai_message_ui`” in `2026-08-01-markdown-semantic-renderer-design.md`  
**Keeps:** single IR path, kind-based `gapBetween`, profiles, registries, LRU compile cache, no `RenderTable`

## Problem

Semantic markdown (compile → IR → `MarkdownView`) lives inside `ai_message_ui`, which couples a reusable document renderer to chat Thread/Part UI, `AiMessageStrings`, and message chrome. That blocks independent versioning, pub-ready packaging, and non-chat hosts (file preview already wants a thin dependency).

## Goals

1. **Standalone Flutter package** `tp_markdown` under `client/packages/tp_markdown/` (path dep today; publish-ready layout).
2. **Zero dependency** on `ai_message_ui` / `ai_message_core`.
3. Preserve **architecture**: GFM parse (`package:markdown`) → compile → style-free IR → tokenized render + registries.
4. Preserve **performance**: compile LRU cache, Column + kind gaps (no markdown `RenderTable`), streaming fence prep.
5. **Host injection** for theme tokens, link/image resolvers, and chrome copy strings.
6. `ai_message_ui` becomes a **consumer** only (chat chrome + wiring). Hosts import `package:tp_markdown` directly — **no re-exports / compat shims**.

## Non-goals

- Publishing to pub.dev in this change (structure + README/CHANGELOG only).
- WYSIWYG / AppFlowy editor.
- Replacing `package:markdown` parser.
- Moving TeamPilot `buildAppMarkdownTokens` into the package (host theme mapping stays in app).

## Package name

**`tp_markdown`** — aligns with Tp design system; publishable later under the same name or renamed without changing IR APIs.

## Boundary

| In `tp_markdown` | Stays in `ai_message_ui` | Stays in app host |
|------------------|--------------------------|-------------------|
| `ir/` | `compiled_markdown_chrome.dart` (tool/reasoning chrome) | `buildAppMarkdownTokens` |
| `tokens/` (`MarkdownTokens`, `MarkdownProfile`, `gapBetween`) | Thread/Part views wiring | Preview `SelectionArea` chrome |
| `compile/` (`compileMarkdown`, streaming, cache, **history truncate**) | `AiMessageStrings` → map into `MarkdownStrings` | |
| `render/` (`MarkdownView` + block widgets) | | |
| `registry/` (`BlockWidgetRegistry`, `MarkdownResolvers`) | | |
| `MarkdownStrings` (English defaults; Inherited or ctor inject) | | |

## Architecture

```
package:markdown (GFM AST)
        │
        ▼
 tp_markdown compile (+ LRU)
        │
        ▼
 MarkdownDocument / MarkdownBlock (style-free IR)
        │
        + MarkdownTokens (host-built) + MarkdownResolvers + MarkdownStrings
        ▼
 MarkdownView → BlockWidgetRegistry → widgets
        │
   ┌────┴────┐
   ▼         ▼
 chat      file preview
 (ai_message_ui)  (app → tp_markdown)
```

### Public barrel

`package:tp_markdown/tp_markdown.dart` exports IR, compile, tokens, view, registry, strings, truncate.

### Extensibility

- **Block widgets:** `BlockWidgetRegistry` (override / extend built-ins).
- **Resolvers:** links + images.
- **Tokens:** value object; profiles drive gap matrix only.
- **Strings:** `MarkdownStrings` (copy / copied / code) — no Material l10n dependency inside the package.
- Future: compile plugins / math / mermaid via registry — not in this extract.

### Performance (must not regress)

- Keep compile LRU (same capacity / keying).
- Keep kind-based gaps only.
- Keep table layout as custom widgets (not Flutter `Table` markdown path).
- Truncate operates on IR (cheap) after compile.

## Migration

1. Add `tp_markdown` package; move modules; fix imports to `package:tp_markdown/...`.
2. Code block chrome: `MarkdownStrings` only (chat maps from `AiMessageStrings` at the call site).
3. `ai_message_ui`: path-depend on `tp_markdown`; **do not** re-export it.
4. App + tests: import `package:tp_markdown` wherever markdown types/APIs are used.
5. Move markdown-focused tests into `tp_markdown/test/`; leave chat-integration tests in `ai_message_ui`.

## Risks

| Risk | Mitigation |
|------|------------|
| Import breakage | Update call sites to `package:tp_markdown` (no shim) |
| String regression | Map `AiMessageStrings` → `MarkdownStrings` in `TextPartView` |
| Accidental product coupling | Analyze `tp_markdown` has no `ai_message_*` imports |

## Success criteria

- `cd client/packages/tp_markdown && flutter test` green.
- `cd client && flutter analyze … && flutter test --exclude-tags integration` green for markdown + preview suites.
- No markdown layout code left under `ai_message_ui/lib/src/markdown/{ir,tokens,compile,render,registry}` except chrome shim / re-exports if any.
