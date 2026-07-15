# Markdown WYSIWYG via AppFlowy Editor

**Status:** Draft  
**Date:** 2026-07-15

## Problem

TeamPilot’s workbench already edits Markdown as source (`re_editor`) with a read-only preview (`flutter_markdown_plus`). There is no editable rich/block view. Users who write Markdown (and later broader “documents”) need a Notion-style WYSIWYG mode without giving up Git-friendly plain `.md` on disk or the existing code editor for non-Markdown files.

## Goals

1. Add a **WYSIWYG** view mode for Markdown paths (`.md` / `.markdown`) alongside existing **Source** and **Preview**.
2. Keep disk format as **plain Markdown** for v1; WYSIWYG is a view over the same text buffer.
3. Integrate the standalone **`appflowy_editor`** package (not the AppFlowy monorepo / Rust backend).
4. Leave a clear extension point for a future native document type without replacing the editor shell.
5. Preserve `EditorCubit` ownership of open / dirty / save and `CodeLineEditingController` as the text source of truth.

## Non-goals (v1)

- Embedding the AppFlowy application monorepo, plugins tree, or Rust/cloud backend.
- Replacing `re_editor` for general source files.
- Strict lossless Markdown round-trip (whitespace, list style, exotic constructs).
- Real-time collaboration, comments, database/kanban blocks, or AppFlowy AI writer.
- Persisting view mode to disk beyond existing `MarkdownOpenMode` preference hooks (session store remains in-memory; optional default may include `wysiwyg`).

## Decisions

| Topic | Choice |
|-------|--------|
| Product shape | Source \| WYSIWYG \| Preview for Markdown only |
| On-disk format (v1) | Pure Markdown; later optional native doc format |
| Editor package | `appflowy_editor` from pub (MPL-2.0 / AGPL-3.0 dual; compatible with TeamPilot AGPL) |
| Source of truth | `CodeLineEditingController.text` via `EditorCubit` |
| Fidelity bar | Common Markdown subset; Source remains the exact-edit escape hatch |
| Mode switch I/O | Switching modes never writes the file; only Save (or existing auto-save) persists |
| Future docs | Same `AppFlowyEditor` shell; swap codec / storage (`MarkdownFileCodec` → native) |

## Architecture

```
FileEditorSurface (.md)
├── MarkdownViewModeToggle  →  source | wysiwyg | preview
├── Source   → CodeEditor (re_editor)                 [existing]
├── Wysiwyg  → AppFlowyEditor + MarkdownWysiwygSession [new]
└── Preview  → MarkdownBody (flutter_markdown_plus)   [existing]

EditorCubit
  · open / dirty / saveFile / CodeLineEditingController (text SoT)

MarkdownWysiwygSession (new)
  · holds EditorState
  · MarkdownBridge: text ↔ Document (common subset)
  · on edit: encode → controller.text → dirty
```

### Key types / modules (proposed)

| Module | Role |
|--------|------|
| `MarkdownViewMode` | Extend enum: `source`, `wysiwyg`, `preview` |
| `MarkdownViewModeStore` / toggle UI | Three-segment control + l10n |
| `MarkdownWysiwygSession` | Per open path: build/dispose `EditorState`, flush, rebuild on external reload |
| `MarkdownBridge` | Thin wrapper around `markdownToDocument` / `documentToMarkdown` (+ optional front-matter prefix handling) |
| `FileEditorSurface` | Branch body on mode; WYSIWYG pane widget |
| Theme adapter | Map TeamPilot / Tp colors & fonts into `EditorStyle` |

Dependency: add `appflowy_editor` to `client/pubspec.yaml`. Register `AppFlowyEditorLocalizations.delegate` on `MaterialApp` if required by the package.

## Mode switching and sync

**Semantics**

| Mode | Behavior |
|------|----------|
| Source | Edit `controller` directly; no Document |
| WYSIWYG | Enter: `markdownToDocument(current text)` → new `EditorState`. Edits encode back to text (debounced) and mark dirty |
| Preview | Read-only render of current text; never writes back |

**Rules**

1. **Source → WYSIWYG:** rebuild `EditorState` from current text (discard stale session).
2. **WYSIWYG → Source / Preview:** if the session has **unflushed WYSIWYG edits**, flush Document → text first; if the user only viewed WYSIWYG without editing, **do not** re-encode (avoids noisy reformatting). Then show Source/`CodeEditor` or Preview (v1: no precise caret mapping).
3. **Mode changes do not write disk.**
4. **Controller text replaced from outside WYSIWYG** (external file reload, `revertFile`, or any non-encoder write to `controller.text`): if WYSIWYG is active, rebuild `EditorState` from the new text and clear the session’s unflushed flag.
5. Debounce WYSIWYG → controller encode (~100–200ms) to avoid full encode per keystroke. On session dispose / tab close, **cancel pending debounce and flush immediately** if there are unflushed edits so the last keystrokes are not lost.

**Unflushed edits:** `MarkdownWysiwygSession` tracks whether Document has changed since the last successful encode into `controller.text`. Entering WYSIWYG starts with no unflushed edits.

`MarkdownOpenMode` may gain an optional default of `wysiwyg` (requires `seedOnOpen` + layout settings UI); otherwise keep current preview / source / remember behavior and only add the third in-session mode.

## Save and fidelity

**Save**

- `saveFile` continues to persist `controller.text` only.
- If the active mode is WYSIWYG **and** the session has unflushed edits, flush Document → text immediately before write. If there are no unflushed edits, write `controller.text` as-is (no re-encode).
- No second dirty channel for disk purposes; WYSIWYG mutations must surface through the controller / existing `EditorCubit` dirty set (encode updates the controller, which marks dirty as today).

**Supported subset (v1)**

- Headings, paragraphs
- Bold / italic / strikethrough / inline code
- Ordered, unordered, and task lists
- Links and images (URL or workspace-relative path)
- Blockquotes, fenced code blocks, simple tables, horizontal rules

**Known lossy / best-effort**

- YAML front matter: **v1 best-effort preserve-prefix** — strip and hold the leading `---` … `---` block outside the Document when entering WYSIWYG, reattach on encode. If the file’s front matter cannot be detected with a simple prefix scan, treat the whole file as body (no special handling) and accept that limitation in docs/help.
- Raw HTML, custom containers, unusual list indentation / blank-line style: accepted loss when the user edits via WYSIWYG and saves.
- Surface in help/UI copy that WYSIWYG save may normalize body formatting; use Source for exact control.

**Links**

- Prefer reusing `handleMarkdownPreviewLink` for in-editor link activation (relative path open, etc.) where the package allows custom handlers.

## Future document writing (out of v1, reserved)

Introduce a codec boundary so a later native document type does not fork the UI shell:

```
DocumentCodec
  · MarkdownFileCodec   // v1: .md on disk
  · NativeDocCodec      // later: e.g. JSON / .afdoc under workspace layout
```

Collaboration, AI assist, and non-Markdown blocks attach after the codec / product type exists—not in this change.

## Testing

1. **Unit:** round-trip fixtures for the common subset via `MarkdownBridge`.
2. **Unit / cubit:** mode switch flushes WYSIWYG → text; mode switch does not call filesystem write.
3. **Widget:** three-segment toggle; WYSIWYG edit marks dirty and save persists Markdown.
4. **Regression:** non-Markdown paths still use only `CodeEditor`.

## Implementation sketch (ordering)

1. Dependency + localizations delegate.
2. Extend `MarkdownViewMode` / store / toggle / l10n.
3. `MarkdownBridge` + round-trip tests.
4. `MarkdownWysiwygSession` + surface pane wired to `EditorCubit`.
5. Flush-on-leave / flush-before-save / external reload rebuild.
6. Theme adapter + link handler wiring.
7. Optional `MarkdownOpenMode.wysiwyg` default.

## Risks

| Risk | Mitigation |
|------|------------|
| Round-trip reformats Markdown (noisy Git diffs) | Common-subset fidelity; Source escape hatch; re-encode only when the WYSIWYG session has unflushed edits (leave mode / save / dispose) |
| Package size / shortcut conflicts with terminal & workbench | Scope editor shortcuts; smoke-test focus in workbench |
| Theme mismatch with Tp | Explicit `EditorStyle` mapping; no AppFlowy default skin dump |
| Front matter / HTML breakage | Preserve-prefix for detectable YAML front matter; keep Preview + Source |
| Upstream API churn (`appflowy_editor`) | Pin a concrete pub version in `pubspec.yaml`; thin bridge isolates call sites; v1 uses package default toolbar/slash menu unless they conflict with workbench chrome (then strip to minimal) |
