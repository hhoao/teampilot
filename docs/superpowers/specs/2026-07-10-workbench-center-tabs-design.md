# Workbench Center Tabs (Orca-style) design

**Date:** 2026-07-10  
**Status:** Approved (spec review)  
**Related:** Floating `WorkspaceFloatingEditor`, modal `GitDiffDialog`, `WorkspaceShell` session tabs, Orca unified editor/diff/terminal tabs

## Summary

Replace the floating file editor and modal git-diff dialog with **Orca-style center workbench tabs**: session, file, and diff tabs share one middle tab bar per title-bar workspace. Clicking a file in the file tree or a change in Source Control opens (or activates) a center tab; the workbench body shows the matching surface.

No backward compatibility. Delete the floating editor host, the modal diff entry path, and the editor’s internal tab bar. Do not leave shims, dual hosts, or “temporary” parallel UIs.

## Goals

| Goal | Description |
|------|-------------|
| Unified center tabs | One tab bar in `WorkspaceShell` for `session` \| `file` \| `diff` |
| Workspace isolation | Open file/diff tabs are keyed by title-bar `workspaceId` (like Orca worktree) |
| Domain separation | Sessions stay in chat; files/diffs stay in editor; a workbench layer owns order + active selection |
| Diff as a tab | Source Control opens a diff tab, not `GitDiffDialog` |
| Single file surface | No floating window; no second tab strip inside the editor |
| Clean delete | Remove floating editor + modal-diff open path entirely |
| Preview replace | Single-click file/diff opens a replaceable preview tab (italic); another preview replaces it; double-click or edit pins |

## Non-goals

- Split groups, combined multi-file diff tabs
- Persisting open file/diff tabs across app restart (model may allow later; not required now)
- Changing right-tools layout, file-tree panel chrome, or git stage/commit flows
- Browser / simulator tab kinds (Orca-only)

## Problem with the current architecture

Today:

1. Center tabs are **session-only** (`ChatCubit` / `ChatTabStore` → `TabInfo`).
2. Opening a file mounts a **floating** `WorkspaceFloatingEditor` over the home stack.
3. The editor keeps a **second** tab bar inside `FileEditorPanel`.
4. Opening a git change uses **`GitDiffDialog.show`** (modal barrier), disconnected from the workbench tab model.
5. `EditorCubit` is a **global** open-file list, not workspace-scoped.

So the center workbench cannot represent “what the user is looking at” when that thing is a file or a diff. Root cause: **editor/diff are overlays beside the tab system instead of first-class workbench tabs.**

## Canonical primitives

| Primitive | Owner | Role |
|-----------|--------|------|
| **Workbench tab** | `WorkbenchCubit` | Ordered identity in the center bar: kind + id + workspaceId |
| **Session tab** | `ChatTabStore` | Terminal/chat surface; content + working state |
| **File tab** | `WorkspaceEditorStore` (via `EditorCubit`) | Editable buffer for one path in one workspace |
| **Diff tab** | same editor store | Read-only diff surface for one path + staged\|unstaged in one workspace |
| **Active selection** | `WorkbenchCubit` | Which workbench tab is showing in the center body |

**Deleted:**

- `WorkspaceFloatingEditor` and its drag/resize chrome
- `FileEditorPanel` internal tab bar (`_FileEditorTabBar`)
- `GitDiffDialog.show` as the Source Control open path (dialog shell may be deleted once content lives in an embeddable panel)
- Global unscoped `EditorState.openPaths` as the sole open-file model

## Architecture

```
WorkspaceShell tab bar
        ▲
        │ List<WorkbenchTab> + activeTabId
        │
 WorkbenchCubit  (per workspaceId bucket)
   ├── reads ChatTabStore          → session tabs
   ├── reads WorkspaceEditorStore  → file + diff tabs
   └── owns tabOrder + activeTabId

ChatWorkbench body
   active kind == session → existing terminal/chat surface
   active kind == file    → FileEditorSurface (single buffer, no inner tabs)
   active kind == diff    → DiffEditorSurface (DiffViewer + reload/open-source)
   tabOrder empty / compose → ComposeLanding (shell stays mounted)
```

### Why a cubit (not a pure function)

Selection and close-neighbor behavior need durable per-workspace state (`tabOrder`, `activeTabId`, last-selected fallback). A pure merge of two lists cannot own “user closed the active diff; restore previous tab.” `WorkbenchCubit` is the single writer for center-bar selection.

### Domain boundaries

- **Do not** put file/diff open lists into `ChatCubit`.
- **Do not** put session PTY/working state into `EditorCubit`.
- Shell UI binds tabs/selection to `WorkbenchCubit` only; body widgets read the owning domain cubit for content.

### Compose landing (required restructure)

Today `WorkspaceSplitPane` swaps the entire main pane to `WorkspaceComposeLandingPane` when `composeActive`, which **unmounts** `ChatPage` / `WorkspaceShell`. That worked with a floating editor mounted above the fork; it is incompatible with center file/diff tabs.

**Rule:** `WorkspaceShell` (tab bar + `WorkbenchBody`) is **always** mounted for an open workspace title-bar tab. Compose is a **body state**, not a shell-unmounting sibling:

```text
WorkspaceShell  (always for workspace)
  tab bar ← WorkbenchCubit.tabOrder
  WorkbenchBody
    ├─ active == session → SessionWorkbench
    ├─ active == file    → FileEditorSurface
    ├─ active == diff    → DiffEditorSurface
    └─ tabOrder empty or explicit compose → ComposeLanding (former WorkspaceComposeLandingPane content)
```

- “New chat” / `enterComposeMode` sets `composeActive` and clears workbench `activeTabId` for that workspace; body shows compose. **Tab bar stays** if any tabs remain in `tabOrder`.
- Any `WorkbenchCubit.select` / `ensureTab` that activates a session|file|diff tab **clears `composeActive`**. Compose and active tab must not disagree: if `activeTabId != null`, body is never compose.
- Opening a session from compose exits compose as today, and registers the session into `tabOrder`.

Delete the `composeActive ? LandingPane : ChatPage` fork in `WorkspaceSplitPane`.

### Session ↔ workbench registration

`ChatTabStore` is the source of session existence. **Every** mutation that adds or removes a session tab in a workspace bucket (create, close, workspace restore/hydration, close-others that drops sessions) must call `WorkbenchCubit.ensureTab(session…)` or `removeTab(session…)` at that call site. Do not rely on a passive store listener.

### Open entrypoints

`EditorCubit.openFile` / `openDiff` (or a thin `WorkbenchEditorOpener` used by all UI) must update the editor bucket **and** call `WorkbenchCubit.ensureTab` in one path so callers cannot open a buffer without a center tab.

### Selection authority

`WorkbenchCubit.activeTabId` is the only selection authority for the center bar and body. Remove `EditorCubit` / `EditorState.activeIndex` as a user-facing selection field; the active file path is derived as “if active tab is file, that path” (buffers stay keyed by path). Chat’s session index updates only when the active workbench tab is a session (sticky otherwise).

## Data model

### Workbench tab identity

```dart
enum WorkbenchTabKind { session, file, diff }

class WorkbenchTabId {
  final WorkbenchTabKind kind;
  final String id; // sessionId | absolutePath | diffKey
}

/// diffKey = "$absolutePath::staged" | "$absolutePath::unstaged"
```

Same path may have a **file** tab and one or more **diff** tabs at once (Orca behavior). Staged and unstaged diffs are **separate** tabs.

### Per-workspace editor bucket

```dart
class WorkspaceEditorBucket {
  final List<String> openFilePaths;
  final Map<String /*diffKey*/, DiffTabState> openDiffs;
  // controllers / dirty / loading keyed by path — existing handle model, scoped here
}

class DiffTabState {
  final String absolutePath;
  final bool staged;
  final String title; // usually repo-relative path
  // reloadDiff callback or enough context for GitCubit to reload
}
```

`EditorCubit` becomes a facade over `Map<String /*workspaceId*/, WorkspaceEditorBucket>` (name the store clearly; avoid a second global list).

### Tab order

`WorkbenchCubit` keeps an explicit `List<WorkbenchTabId> tabOrder` per workspace:

- Opening a **new** session always **appends**. File/diff opens default to **preview**: a new preview replaces the existing file/diff preview in-place; permanent opens append (or activate + pin if already open).
- Re-opening an existing id **activates** it; does not duplicate.
- Closing removes from `tabOrder` and domain store.
- Session tabs that appear from chat still register into `tabOrder` when created; removing a session removes that id from `tabOrder`.

Display titles/icons:

| Kind | Title | Icon / accent |
|------|-------|----------------|
| session | existing session title | CLI brand / terminal (unchanged) |
| file | `basename(path)`; dirty indicator | file icon |
| diff | path (+ staged/unstaged label if both open) | diff icon |

## Interactions

### Open file (file tree, search, terminal link, git “open source”)

1. Resolve current `workspaceId`.
2. Clear compose for that workspace if active.
3. `EditorCubit.openFile(workspaceId, path, fs: …)`.
4. `WorkbenchCubit.ensureTab(workspaceId, file(path))` → set active.
5. Center body shows `FileEditorSurface` for that path (shell already mounted).

### Open diff (Source Control row)

1. Clear compose for that workspace if active.
2. `EditorCubit.openDiff(workspaceId, path, staged: …)` (load initial diff text via `GitCubit`).
3. `WorkbenchCubit.ensureTab(workspaceId, diff(diffKey))` → set active.
4. Center body shows `DiffEditorSurface` (former `GitDiffDialog` content: `DiffViewer`, ignore-whitespace / full-context reload, open source → `openFile`).

### Select tab

- `WorkbenchCubit.select(workspaceId, tabId)`.
- If kind == session → also `ChatCubit.selectTab` for that session (terminal focus / selected member semantics unchanged).
- If kind == file \| diff → do **not** close or clear the last session; terminal stays mounted offstage or kept alive as today for inactive session tabs. Presence/bus continue to follow chat’s selected session unless product later ties them to workbench active (out of scope: keep chat selection sticky when browsing files).

### Close tab

| Kind | Behavior |
|------|----------|
| file | Existing unsaved discard/save prompt, then close buffer + remove from order |
| diff | Close immediately |
| session | Existing session close pipeline; remove from workbench order |

After closing the **active** tab: activate the previous tab in `tabOrder` (Orca-like neighbor), else the next, else when `tabOrder` is empty show compose landing in the body.

`closeOthers` / `closeRight` operate on `tabOrder` indices and dispatch to the correct domain closer per kind.

### Workspace title-bar switch

Each title-bar workspace has its own `tabOrder` + editor bucket + chat tab bucket. Switching title-bar tabs shows that workspace’s workbench state; no global shared file tabs.

## UI structure

### `WorkspaceShell`

- `tabs` / `activeTabIndex` / close handlers come from `WorkbenchCubit` projection for the current `workspaceId` (mapped to `TabInfo` for rendering).
- Extend `TabInfo` (or replace with a richer view model) so file/diff can set icon and dirty without pretending to be a CLI session.

### Center body

`WorkbenchBody` switches on active kind (chat-terminal code does not own editor layout):

```text
WorkbenchBody
  ├─ SessionWorkbench (existing terminal stack)
  ├─ FileEditorSurface   // CodeEditor for active path only
  ├─ DiffEditorSurface   // DiffViewer + toolbar
  └─ ComposeLanding      // when tabOrder empty or compose requested
```

Right tools remain hosted by the shell layout (same as today’s `ChatPageShell` / `RightToolsHost`), so file tree and git stay available during compose and while a file/diff tab is active.

### Removals

- `HomeWorkspaceBodyStack` no longer mounts `WorkspaceFloatingEditor`.
- Delete floating window positioning/resize widgets tied only to that host.
- Delete `WorkspaceSplitPane`’s `composeActive ? Landing : ChatPage` fork; compose content moves into `WorkbenchBody`.
- Source Control `_openDiff` must not call `showDialog` / `GitDiffDialog.show`.
- Delete `EditorState.activeIndex` as selection; path buffers are keyed by path only.

## Error handling

- Failed file load: keep the file tab; show inline error in `FileEditorSurface` (existing error-by-path pattern).
- Failed diff load: keep the diff tab; show empty/error state with retry via reload.
- Missing `workspaceId` at open call sites: treat as a programming error (assert / log); do not fall back to a global bucket.

## Testing

| Area | Cases |
|------|--------|
| `WorkbenchCubit` | ensure/activate/dedupe; close neighbor selection; closeOthers/closeRight across mixed kinds; per-workspace isolation |
| `EditorCubit` buckets | file open scoped by workspace; staged vs unstaged diff keys; file+diff same path coexist; close file leaves diff |
| `WorkbenchBody` | kind switches render correct surface; empty `tabOrder` → compose |
| Compose | open file/diff from tree/git while compose active exits compose and shows center tab; shell tab bar never unmounts |
| Git panel | open diff activates center tab; no dialog route |
| Regression | dirty file close prompt; session working spinner still on session tabs only |

## Success criteria

1. Clicking a file tree file opens a **center** file tab in the current workspace; no floating editor.
2. Clicking a git change opens a **center** diff tab; no modal diff dialog.
3. Session, file, and diff tabs share one bar and can be switched without losing the others.
4. Switching title-bar workspace hides the other workspace’s file/diff tabs.
5. No internal editor tab strip; no dual open-file hosts.
6. Compose no longer unmounts `WorkspaceShell`; opening a file during compose works without a floating overlay.

## Implementation notes (architecture, not schedule)

- Introduce `WorkbenchCubit` and workspace-scoped editor buckets **before** deleting the floating host, but ship deletion in the same change set — no release with both UIs.
- Extract `DiffEditorSurface` from `GitDiffDialog` content; delete the dialog entry API once callers are gone.
- Rename or split oversized `file_editor_panel.dart` so floating chrome is not left as dead code beside the surface.
- All `openFile` / `openDiff` call sites must pass `workspaceId` explicitly.
