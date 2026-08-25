# Manual session groups in the workspace sidebar

## Goal

Let users organize sessions into named groups (for example a "todo" group) in
the left Session sidebar of a workspace.

## Decisions

- **Tag-style membership.** A session can belong to multiple groups at once.
  Group members stay visible in their normal position (main list or worktree
  group); the group block is an additional view, like the running-sessions
  strip.
- **Workspace scope.** Groups are defined per workspace and never span
  workspaces.
- **Inline collapsible blocks.** Each group renders as a collapsible section
  with a header row and member rows, following the `WorktreeGroupSection`
  interaction model.
- **Context-menu add/remove.** Membership is changed from the session row's
  context menu; no drag-and-drop in this iteration.
- **Always on top.** Group blocks render above the conversation list in both
  flat layout and automatic worktree-grouped layouts; manual grouping is
  orthogonal to worktree grouping.
- **Dedicated storage.** Groups live in their own per-workspace file, managed
  by a dedicated repository and cubit. Existing models (`Workspace`,
  `AppSession`) are not extended.

## Data model

New file `client/lib/models/session_group.dart`:

```dart
class SessionGroup {
  final String id;               // uuid
  final String name;
  final List<String> sessionIds; // members; multi-membership allowed
  final bool collapsed;          // persisted collapse state
}

class SessionGroupsFile {
  final int version;             // currently 1
  final List<SessionGroup> groups;
}
```

- Persistence path: `{workspaceId}/session-groups.json`, exposed as
  `WorkspaceLayout.sessionGroupsFile(workspaceId)`; all IO through
  `AppStorage.fs`.
- Member rows inside a block render in the workspace session order produced by
  the current sort (`sortAppSessions`); no separate member ordering is stored.
  Deleted sessions are filtered out at render time and pruned from
  `sessionIds` the next time the file is saved.
- Group display order equals array order in the file; new groups append.

## State management

New file `client/lib/cubits/session_groups_cubit.dart`:

- `SessionGroupsState { status, groups }`; loads for the active workspace and
  reloads when the workspace changes (hydrate pattern of `WorktreeCubit.load`).
- API: `createGroup(name)`, `renameGroup(id, name)`, `deleteGroup(id)`,
  `addSession(groupId, sessionId)`, `removeSession(groupId, sessionId)`,
  `toggleCollapsed(id)`.
- Every mutation updates state optimistically, then persists the whole file.
- Provided next to `WorktreeCubit` in `workspace_split_pane.dart`.

A small repository/store wraps load/save of `session-groups.json`.

## UI

### Group block

New component `client/lib/pages/home_workspace/workspace/session_group_section.dart`,
modeled on `WorktreeGroupSection`:

- Header row: group name + member count + collapse chevron. On hover, a "+"
  action opens a dialog listing this workspace's sessions; entries for
  sessions already in the group are checked and unchecking them removes the
  session from the group. A right-click menu offers rename and delete
  (delete confirms first).
- Member rows reuse `SidebarSessionTile` so open/pin/context behavior matches
  the main list exactly. Rows beyond the display cap collapse behind a
  show-more row, reusing the existing pattern.
- Empty groups show a placeholder row ("no conversations").

### Sidebar integration

- `_ConversationListHost` renders one block per group above the existing list
  (flat mode) or above the worktree group sections (grouped modes).
- The section header row gains a "+" icon button next to the sort/worktree
  buttons; it opens a name dialog (`TpInput` + `TpButton`) that creates a
  group.

### Session row menu

`SidebarSessionTile`'s context menu / long-press menu gains an "Add to group"
submenu listing every group. Items for groups already containing the session
show a checkmark; activating such an item removes the session from that group.

## Edge cases

- Deleting a group never touches its member sessions.
- Deleting a session: blocks skip missing ids at render time; ids are pruned
  on the next save.
- Missing or corrupt `session-groups.json`: treat as empty, rebuild the file,
  log a warning via `AppLogger`.
- Workspace switch: cubit reloads the new workspace's file.

## l10n

All user-facing strings (create/rename/delete labels, add-to-group submenu,
empty placeholder, confirm dialog) go in `app_en.arb` and `app_zh.arb`.

## Tests

- Store/repository unit tests: CRUD round-trip, corrupt-file tolerance,
  pruning of stale session ids.
- Cubit tests under `setUpTestAppStorage()`: create/rename/delete/add/remove/
  toggle-collapse, optimistic state updates.
- Widget tests: create entry point, rename/delete via header menu,
  context-menu add/remove membership, collapse persistence across rebuilds.
