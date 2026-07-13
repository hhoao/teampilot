# Markdown preview + link/table polish — Design

**Date:** 2026-07-14  
**Status:** Approved  
**Related:** [AI Message UI polish](2026-07-14-ai-message-ui-polish-design.md), open-source `assistant-ui` `markdown-text.tsx`, IDE `FileEditorSurface` / `FileDiffSurfaceToggle`

## Goal

1. Close remaining markdown **link / table** visual gaps vs assistant-ui in `ai_message_ui` (and shared app sheet).
2. When the file tree opens `.md` / `.markdown` in the workbench editor, support **Source | Preview** toggle with a user-configurable default open mode.

## Non-goals

- Syntax highlighting inside code blocks (follow-up)
- Side-by-side source + preview
- Editing inside preview
- Complex local image path resolution / asset hosting
- New workbench tab kinds for preview
- Persist per-file last mode across app restarts (session memory only for `remember`)

## Scope

| # | Change | Where |
|---|--------|--------|
| 1 | Link + table styles closer to aui | `ai_message_ui` `defaultAiMarkdownSheet`; app `buildAppMarkdownStyleSheet` |
| 2 | Optional link tap hook in package | `AiTextPartView` / markdown host |
| 3 | Source \| Preview toggle for markdown files | `FileEditorSurface` toolbar |
| 4 | Live preview from editor buffer | Preview body listens to `CodeLineEditingController` |
| 5 | Open-mode preference | `LayoutPreferences` + Layout appearance settings UI |
| 6 | Link navigation in IDE preview | http(s) → system browser; workspace-relative → `WorkbenchEditorOpener` |

---

## 1. Markdown link / table polish

### Package (`ai_message_ui`)

Extend `defaultAiMarkdownSheet`:

| Element | Treatment |
|---------|-----------|
| `a` | `colorScheme.primary`, underline (+ underline offset if easy with `TextStyle`) |
| Table | Muted header fill; thin outline-variant borders; cell padding ~12×6; head semibold |
| Link tap | Optional `onTapLink` on `AiTextPartView` / thread host — **no** `url_launcher` dependency in the package |

Do not attempt pixel-perfect CSS `border-separate` first/last cell radii; Flutter `Table` approximate is enough.

### App sheet

Mirror the same link/table tokens in `buildAppMarkdownStyleSheet` so History Thread and IDE preview share look.

---

## 2. IDE Source | Preview

### Trigger

Path extension is `md` or `markdown` (same allowlist / language registry already used by the editor).

### UI

- Toolbar control modeled on `FileDiffSurfaceToggle`: compact **Source | Preview** pill.
- Shown only for markdown paths; coexist with File | Diff (markdown toggle is independent; Diff still swaps workbench tab kind).
- **Source:** existing `CodeEditor` path (edit, dirty, save, tree-sitter).
- **Preview:** scrollable `MarkdownBody` with `buildAppMarkdownStyleSheet`, reading `controller.text` via `ListenableBuilder` (or equivalent). Unsaved edits appear immediately.

### State

- One `CodeLineEditingController` per open path — mode flip must not reload or clear dirty.
- **Require** a process-lifetime, path-keyed in-memory map for Source|Preview (same store `remember` uses). Do **not** rely on widget-local state alone — File↔Diff disposes `FileEditorSurface` and would otherwise lose the mode.
- **Seed rules**
  - Surface / body reads mode from the map. If missing, seed from preference (`preview` / `source`; `remember` with no entry → `preview`) and write the map.
  - Toolbar toggle updates the map only (preference is not re-applied on focus).
  - On `openFile` for a path: if preference is `preview` or `source`, **set** the map entry to that preference (so reopening honors the setting). If preference is `remember`, keep any existing map entry; if none, seed `preview`.
  - Changing the preference mid-session does **not** remount already-open tabs; it applies on the next `openFile` / first seed for a path.

### Links in preview

| Href | Action |
|------|--------|
| `http://` / `https://` | Launch with existing app URL helper / `url_launcher` |
| Absolute file under workspace root | `WorkbenchEditorOpener.openFile` |
| Relative path | Resolve against markdown file’s directory; if under workspace and openable, open in editor; else **silent no-op** |
| Other schemes | Ignore (skip `mailto:` etc. in v1) |

Chat / History Thread: this plan only polishes link/table **styles**; wiring `onTapLink` there is optional and not required for success.

---

## 3. Configuration

### Preference

Add to `LayoutPreferences` (persisted JSON):

```dart
enum MarkdownOpenMode { preview, source, remember }
// default: preview
```

| Value | On `openFile` for a markdown path |
|-------|-----------------------------------|
| `preview` | Set session map → Preview |
| `source` | Set session map → Source |
| `remember` | Keep existing map entry if any; else seed Preview |

Session map: **in-memory** for the process lifetime — not written to disk. Survives File↔Diff. Entries may remain after tab close so `remember` restores on reopen within the same app session.

### Settings UI

Layout → Appearance (or Editor subsection if one exists): dropdown / segmented control:

- Title: open Markdown files as…
- Options: Preview / Source / Remember last (session)

l10n: `app_en.arb` + `app_zh.arb`.

---

## Architecture (recommended)

```
File tree tap
  → WorkbenchEditorOpener.openFile  (unchanged)
  → FileEditorSurface
       ├── toolbar: [Save…] [Source|Preview?] [File|Diff?]
       ├── body Source → CodeEditor
       └── body Preview → MarkdownBody(controller.text) + onTapLink
LayoutCubit.preferences.markdownOpenMode
  → initial mode + settings UI
```

No new packages. Preview reuses `flutter_markdown_plus` already in the app / `ai_message_ui`.

---

## Testing

| Layer | Coverage |
|-------|----------|
| `ai_message_ui` | Widget/style smoke: link style present; table renders without overflow for a small GFM table |
| App | `LayoutPreferences` round-trip for `markdownOpenMode` |
| App widget | Markdown path shows toggle; switching keeps dirty flag; preference `source` opens Source |

---

## Success criteria

1. Chat / history markdown links look primary + underlined; tables have distinct header + borders.
2. Opening a `.md` from the file tree shows Preview by default (until user changes preference).
3. Source | Preview toggle switches without losing unsaved edits.
4. Preference `source` / `remember` behave as specified.
5. Preview http(s) links open externally; in-workspace relative links open in the editor when possible.

## Implementation order

1. Link/table sheet polish (+ tests)
2. Preference model + settings UI + l10n
3. `FileEditorSurface` toggle + preview body + link handler
4. Wire initial mode from preference / remember map
5. Verify analyze + targeted tests
