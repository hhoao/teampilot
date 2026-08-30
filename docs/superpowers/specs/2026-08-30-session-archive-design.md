# Session archive — Design

**Date:** 2026-08-30
**Status:** Approved (conversation); awaiting spec review

## Problem

The workspace session sidebar exposes permanent delete on every row
(`SidebarSessionTile` hover trash + overflow “删除”). Finished or idle
conversations clutter the main list, but users often want to hide them
without destroying disk state, open tabs, or running PTYs. True delete
should be a deliberate action in a dedicated archive view.

## Goals

1. Main session list shows only **non-archived** sessions.
2. Row action in the main list is **Archive** (not Delete): one click, no
   confirmation.
3. Sidebar can switch into an **Archive view** that replaces the session
   list; a back control returns to the main list.
4. Archive view lists archived sessions for the current workspace; click
   opens / selects the session like the main list.
5. Archive row actions: **Restore** (one click) and **Delete** (confirm
   dialog, then existing `deleteSession`).
6. Archive and restore are **list filters only** — do not close tabs,
   disconnect PTYs, or move session directories.
7. Search, project grouping, and worktree session lists match the main
   list: exclude archived sessions by default.

## Non-goals

- Moving session directories to a separate on-disk archive tree.
- Cross-workspace archive library or global archive page.
- Bulk archive / empty-all-archive.
- Auto-archive policies (age, inactivity).
- Changing OS notification or idle-notify behavior.
- Keeping the old two-click “arm then confirm” delete control on the
  main list (replaced by archive; archive-view delete uses a dialog).

## Decisions (from brainstorming)

| Topic | Choice |
|-------|--------|
| Entry | Sidebar local view swap (`_showingArchive`), not a chip filter or separate route |
| Restore | Allowed from archive view |
| Running session | Keep tab / PTY; archive is visibility only |
| Open from archive | Same as main list |
| Confirm UX | Archive & restore: one click; delete: dialog |

**Persistence approach:** soft flag on `AppSession` / `session.json`
(recommended over moving dirs or a separate id index).

## Design

### 1. Data model

Add to `AppSession`:

```dart
final bool archived; // default false
```

- Persist as `"archived": true` in `session.json` when archived.
- Missing / absent field deserializes as `false` (backward compatible).
- No `archivedAt` in v1; archive-view sort reuses existing session sort
  (`updatedAt` / manual / etc.).

`copyWith` must support clearing/setting `archived`. Repository
`updateSession` / save path already used for pin/reorder — archive
flips the same way.

### 2. Repository & Cubit API

`SessionRepository` (or thin helpers used by cubit):

- `Future<AppSession?> setSessionArchived(String sessionId, bool archived)`

`ChatCubit`:

- `Future<void> archiveSession(String sessionId)` → `setSessionArchived(..., true)`, replace snapshot.
- `Future<void> unarchiveSession(String sessionId)` → `setSessionArchived(..., false)`, replace snapshot.
- `deleteSession` unchanged (closes tab, clears drafts, deletes dir).

On persist failure: do not leave UI in a lying state — keep previous
snapshot (or revert optimistic update) and show a toast.

Archive / unarchive **must not** call disconnect, `removeSession` tab
paths, or workbench `onSessionDeleted`.

### 3. List filtering

Centralize filtering so all sidebar consumers stay consistent:

```dart
List<AppSession> activeSessions(List<AppSession> sessions) =>
    [for (final s in sessions) if (!s.archived) s];

List<AppSession> archivedSessions(List<AppSession> sessions) =>
    [for (final s in sessions) if (s.archived) s];
```

Apply after `sessionsForWorkspace` (or inside a small helper that takes
workspace + all sessions + archive mode).

Consumers that must exclude archived by default:

- `WorkspaceSidebar` main list / `SessionListStructure`
- Project / group sections fed by that structure
- Worktree session rows in the sidebar
- `workspace_search_dialog` session hits

Archive view uses `archivedSessions` only.

Open / select / History for an already-open archived tab remain
unchanged; the session stays in `ChatState.sessions`.

### 4. Sidebar UI

`WorkspaceSidebar` local state:

```dart
bool _showingArchive = false;
```

When `_showingArchive == false` (main):

- Existing chrome (automations, new chat, search, grouping, sort, …).
- Entry control to open archive: list-header action (near sort / group
  controls) labeled via l10n (“归档” / “Archive”). Always visible;
  zero archived sessions still opens the archive view with the empty
  placeholder.

When `_showingArchive == true`:

- Replace the session list region with archive list + empty placeholder.
- Header shows archive title + back (sets `_showingArchive = false`).
- Hide new-chat / new-group / worktree-create actions in archive view
  (those belong to the active list). New sessions are always
  `archived: false`.

`SidebarSessionTile` mode:

| Mode | Primary destructive/utility control | Overflow |
|------|-------------------------------------|----------|
| Active (default) | Archive icon — one click → `archiveSession` | Rename, duplicate, pin, reference, **Archive** (no Delete) |
| Archive | Restore + Delete | Restore; **Delete** (destructive) |

Delete in archive mode:

1. Show confirm dialog (`Tp` / existing confirm pattern).
2. On confirm → existing `deleteSession`.

Remove the arm-then-confirm trash widget from the active mode path.

### 5. l10n

Add EN + ZH strings (arb only), e.g.:

- Archive / 归档 (action + view title + entry control)
- Restore / 恢复
- Archive empty / 暂无归档会话
- Delete confirm: reuse existing delete-conversation dialog copy where possible

### 6. Error handling

| Failure | Behavior |
|---------|----------|
| Archive/unarchive persist fails | Revert snapshot; toast |
| Delete cancel | No-op |
| Delete fails | Existing delete error path |

## Testing

- `AppSession` JSON: `archived` round-trip; missing field → false.
- Repository: set archived persists and reloads.
- Cubit: archive removes from active filter, adds to archived; unarchive
  reverses; neither closes tabs / calls delete.
- Widget / sidebar tile: active mode has archive, no delete; archive mode
  has restore + delete dialog; confirm calls delete.

## Implementation notes

- Prefer filtering helpers under `client/lib/utils/session/` next to
  `workspace_sessions.dart`.
- Keep `SidebarSessionTile` file size in check: extract archive vs active
  trailing actions if the widget grows further.
- No new route; archive is sidebar-local UI state only.

## Open follow-ups (out of scope)

- Sort archive list by archive time (`archivedAt`).
- Badge count of archived sessions on the entry control.
- “Archive and close tab” as an optional modifier.
