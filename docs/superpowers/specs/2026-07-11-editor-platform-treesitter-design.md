# Editor Platform (Tree-sitter)

**Date:** 2026-07-11  
**Status:** Approved  
**Constraints:** Pure Flutter; no backward compatibility; optimize for architecture, performance, UX, extensibility; workload unconstrained.

## Problem

TeamPilot’s file/diff editors use vendored `re-editor` + `re_highlight`. Highlighting runs as a **whole-document** pass on a **per-editor Isolate**. Opening a file paints plain text first; colors appear ~1s later after Isolate cold start + full highlight. That is a deliberate trade-off in re-editor, not an app bug — but it fails IDE-grade “open with color” UX.

[flutter-code-editor](https://github.com/akvelon/flutter-code-editor) is not a fix: same highlight.js family, sync on `TextField`, weak on large files.

## Decision

Build a TeamPilot-owned **EditorPlatform** with **Tree-sitter** as the language engine. Keep a **forked `re-editor`** only as the layout/input/scroll shell. Delete the `re_highlight` + per-instance Isolate highlight path.

Out of scope for this phase: real LSP/diagnostics/completion/go-to-definition implementations (interfaces only), custom language-pack install UI, semantic highlighting, replacing re-editor’s layout engine.

## Architecture

```text
App (FileEditorSurface / Diff)
        │
        ▼
EditorPlatform                    ← TeamPilot-owned
  ├─ LanguageRegistry             language packs
  ├─ DocumentSession              per open doc: source ↔ tree ↔ tokens ↔ decorations
  ├─ TokenizationScheduler        viewport-sync first; rest incremental background
  ├─ DecorationModel               search / folds / future diagnostics
  └─ LanguageFeatures*            stubs (hover / complete / definition)
        │
        ▼
re-editor (fork)                  paint TextSpan / input / large-text scroll
        │
        ▼
tree-sitter (FFI)                 incremental parse; grammars loaded on demand
```

### Layering

| Layer | Owns | Must not |
|-------|------|----------|
| `pages/workbench`, diff widgets | UI chrome | grammars / tokenize |
| `cubits/editor_cubit` | file IO, dirty, session lifecycle | highlight algorithms |
| `services/editor_platform/` | registry, session, scheduler, theme | widgets |
| `packages/re-editor` | render + input | language knowledge |

## Tokenization & performance

### Ownership model (normative)

- **One parse tree per `DocumentSession`, owned by a single worker isolate** dedicated to that session’s language runtime (workers come from a shared pool of 1–2 isolates; a session is pinned to one worker for its lifetime).
- The UI isolate never mutates the tree. It sends ordered commands (`open` / `edit` / `queryRange` / `dispose`) over a session channel; the worker applies them **serially** (no concurrent edit+query on the same tree).
- **Viewport-first UX:** the UI may request `queryRange(viewport)` and **block the open/frame path awaiting that reply** (with the frame budget below). It does not run a second parallel tree on the UI isolate.
- Token results are immutable snapshots applied on the UI isolate; stale replies (sequence < latest edit seq) are dropped.

### Open

1. Create `DocumentSession` bound to the editing controller; assign a pooled worker.
2. Resolve `LanguagePack` via registry; `ensureLoaded` grammar on that worker (startup/first-use prewarm for built-in languages so common opens skip the slow path).
3. Await worker `queryRange(viewport ± buffer)` → first frame colored.
4. Enqueue background `queryRange` for the rest of the file on the same worker. Updates paint only affected lines.

### Edit

- UI sends incremental `edit` (byte range + text) with a monotonic seq; worker applies tree-sitter incremental edit then answers follow-up range queries.
- Re-query only lines covered by the dirty subtree (plus viewport if overlapping).
- If awaiting a viewport query exceeds a frame budget (~4–8ms), paint with prior tokens and deliver the update when the worker replies (no flash to unstyled).

### Scroll

- Entering untokenized ranges: request sync-priority `queryRange` for that band on the session’s worker.
- Token cache for far-off-viewport lines may LRU-evict; the worker keeps the parse tree until session dispose.

### Limits

- Huge files: always editable; background colorize is rate-limited; highlighting never blocks input keystrokes (edits are enqueued; paint stays responsive).
- Unknown extension / no pack: plain text, no highlighter and no substitute grammar.

## LanguagePack & registry

**LanguagePack**

- `id` (e.g. `dart`, `typescript`)
- `extensions` / `filenames`
- `grammar` — tree-sitter language binary (packaged per platform or extracted under app support)
- `highlightsQuery` — captures → scopes
- Optional: `foldsQuery`, `localsQuery`
- `featureHooks` → `LanguageFeatures` (null/stub this phase)

**LanguageRegistry**

- Register built-ins at bootstrap. **Required first-wave packs** (real grammars only — no cross-language fakes):
  - `dart`, `json`, `yaml`, `markdown`, `python`, `rust`, `typescript` (also `.js`/`.jsx`/`.mjs`/`.cjs`), `bash`, `xml` (also `.html`/`.htm`), `toml`, `css` (`.css` only)
- `.scss` is plain text this phase (no css stand-in).
- Drop today’s stand-ins (`toml→yaml`, `css/scss→xml`). Until a real pack exists for an extension, treat as plain text.
- `resolve(path) → LanguagePack?`
- `ensureLoaded(id)` with process-wide grammar cache + optional prewarm
- Replace scattered `highlightLanguageKeyForPath` / direct `re_highlight` language imports

### Native / packaging

- Tree-sitter via **Dart FFI** to the official C runtime (one plugin/package under `client/packages/` or `services/editor_platform` native glue).
- Grammars: **ship platform `.so`/`.dylib`/`.dll` artifacts** in the app bundle (native assets via `teampilot_tree_sitter`). No wasm. No runtime download. Lazy `ensureLoaded` + optional prewarm.
- Android + desktop are in scope; grammar load failure → plain text for that session, logged via `AppLogger`.

**Theme**

- `EditorSyntaxTheme`: TextMate-style **scope → TextStyle** (not highlight.js class names).
- Light/dark themes aligned with current atom-one look; app `ColorScheme` swaps theme maps only.
- Language packs stay theme-agnostic.

**Extensibility**

- New language = new pack assets + registry entry; zero `CodeEditor` core changes.
- Model allows later workspace/third-party packs without redesign (install UI later).

## re-editor fork changes

**Delete**

- `_CodeHighlightEngine`, `re_highlight` dependency, per-editor `IsolateManager` highlight tasker

**Add**

- `CodeTokenProvider` (name flexible): per-line `List<TokenSpan { offset, length, scope }>`
- `DocumentSession` implements the provider; editor paints scopes via `EditorSyntaxTheme`

**Keep**

- Line layout, input, selection, bidirectional scroll, find UI hooks, chunk/fold chrome

Folding data may later come from `foldsQuery`; keep chunk UI, swap data source when ready.

## App integration

- `EditorPlatform.bootstrap()` in app shell bootstrap (registry + optional prewarm).
- `EditorCubit` creates/disposes `DocumentSession` with the file controller.
- `FileEditorSurface`: one writable `DocumentSession` per open path.
- Diff panes: **two read-only `DocumentSession`s** (original + modified), same `LanguagePack` from the file path, independent trees/workers as assigned by the pool. No shared mutable tree across panes.
- Remove `codeHighlightThemeFor` / `re_highlight` from `file_editor_theme.dart`; inject `EditorSyntaxTheme`.

## LanguageFeatures (stubs only)

Interfaces reserved for a later phase, e.g.:

- `hover`, `completion`, `definition`, `diagnostics`

No network/LSP clients in this phase. Highlighting and decorations must not depend on these implementations existing.

## Success criteria

1. Common languages: viewport colored on first paint; no ~1s plain→color flash.
2. Large-file typing not stalled by highlighting.
3. Adding a language is pack-only.
4. File editor and diff share one coloring stack.
5. No `re_highlight` in the editor highlight path.

## Non-goals (this phase)

- Shipping LSP / analyzer integrations
- User-facing language pack marketplace/UI
- Semantic token providers
- Replacing re-editor’s text layout engine
- Embedding Monaco / CodeMirror / WebView editors

## Migration stance

Break freely: drop old theme APIs, language key helpers, and highlight isolate behavior. No compatibility shims for `CodeHighlightTheme` / `re_highlight` modes.
