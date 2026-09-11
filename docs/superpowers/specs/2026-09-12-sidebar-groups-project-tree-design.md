# Sidebar Groups and Project Tree Design

Date: 2026-09-12
Status: Approved

## Problem

The workspace sidebar currently renders manual conversation groups and
worktree-based conversation sections in the same conversation area. A
workspace with several worktrees can therefore look like a long, technical
list, while the user's primary mental model is usually the project directory.

The sidebar needs two explicit views so these concepts do not compete for the
same vertical space:

- `# 分组` for manually tagged conversation groups;
- `📁 项目树` for project-directory conversation browsing.

The groups view is the default whenever a workspace sidebar is opened.

## Goals

- Add a compact two-option view switcher matching the supplied reference
  image's segmented-tab treatment.
- Keep `# 分组` as the default view.
- Keep the existing manual-group behavior, including tag-style membership,
  group collapse, rename/delete, and adding conversations.
- Add a project tree with one level of project-directory nodes and
  conversation children:

  ```text
  📁 huji
    conversation A
    conversation B
  📁 another-project
    conversation C
  ```

- Keep conversations with no matching workspace folder in an `Other` node.
- Sort project-tree conversation children using the sidebar's selected session
  sort.
- Preserve worktree-aware launch and working-directory behavior outside the
  sidebar browsing presentation.
- Keep global sidebar actions (new conversation, search, archive, and workspace
  management) available without changing their existing responsibilities.

## Non-goals

- Do not show Git worktree or branch nodes in the project tree.
- Do not show Git worktree or branch nodes in either sidebar browsing view.
- Do not remove worktree support from compose, session launch, IDE, or runtime
  working-directory selection.
- Do not change manual-group membership semantics. A conversation may remain in
  one or more manual groups and the ungrouped conversation list, as it does
  today.
- Do not introduce a new project-management model, route, or project CRUD
  workflow.
- Do not persist the selected sidebar view; opening the workspace always starts
  in `# 分组`.

## UI and interaction

Replace the current conversation-section title row with a sidebar-local
switcher containing:

```text
[ # 分组 ] [ 📁 项目树 ]                         [sort] [archive]
```

The selected segment uses the existing TeamPilot active-surface styling. The
icon-only controls retain their current tooltips and accessibility labels.

The existing top-level action area remains unchanged. The archive view keeps
its current back-navigation behavior; while archive is open, the view content
is replaced by archived conversations and the switcher is not used to alter
archive filtering.

In `# 分组`:

- show the existing manual group blocks first;
- show one flat conversation list below them; it must not switch to
  worktree-grouped sections;
- show the new-group action only in this view;
- retain the current sort and drag-reorder behavior.

In `📁 项目树`:

- render one collapsible node for each `WorkspaceFolder`;
- use the folder directory name as its label;
- render active conversations below the matching folder node;
- render an `Other` node only when conversations do not match any folder;
- do not render worktree refresh, create, or worktree-header management
  actions in this view;
- keep conversation tiles' existing open, active, working, and context-menu
  behavior.

Project nodes are expanded by default for the lifetime of the sidebar. Their
collapse state is held by the project-tree widget and is not written to the
existing worktree preference file. This avoids giving project nodes a Git
worktree persistence meaning and keeps the first version focused.

## Project grouping and data flow

The project tree is a pure projection of existing workspace and chat state; it
does not create or mutate session data.

1. `WorkspaceSidebar` owns a local `WorkspaceSidebarView` enum, initialized to
   `groups`.
2. `_ConversationListHost` selects the active sessions and the existing
   `AppSessionSort` value.
3. In project-tree mode, a pure grouping helper assigns each session to the
   longest matching `WorkspaceFolder.path` prefix, using the repository's
   injected path-normalization rules.
4. Each project bucket is rendered as a collapsible project node. The node's
   children use the existing `SidebarSessionTile` and open the session through
   `openWorkspaceSessionTab`.
5. Sessions not assigned to any folder are placed in a trailing `Other` bucket.

Folder matching uses the session's primary folder path and is independent of
the current Git worktree probe. This means the project tree can render while
worktree discovery is loading and does not change when the user switches the
current worktree. If duplicate folder basenames exist, the implementation
must preserve a distinguishable label by appending the minimum useful parent
path segment; the matching key remains the normalized full folder path.

The current `WorktreeCubit` remains wired because compose and launch flows use
it to select a session working directory. The sidebar's worktree-grouped
rendering path and worktree-specific section actions are removed from both
browsing views.

## State and compatibility

No persistence schema changes are required.

- Existing `session-groups.json` data is read and written unchanged.
- Existing `AppSession` data and workspace folder data are unchanged.
- Existing worktree UI preferences remain available to the compose/runtime
  flows that use them, but no longer control project-tree collapse state.
- Switching sidebar views does not alter session order, group membership,
  current worktree, or active workbench tabs.
- A workspace with no folders renders the normal empty state in project-tree
  mode. A workspace with folders but no active sessions renders its existing
  no-conversations state inside the tree view.

## Error handling

Project grouping is pure and should not perform IO or throw for malformed
session paths. Empty or invalid paths simply fail to match a project and are
shown under `Other` when a session exists. User-facing empty/error copy uses
the existing localized empty-state patterns; diagnostics, if needed, use
`AppLogger`.

The project tree must not wait for or fail because Git worktree discovery is
unavailable. Git errors remain owned by the existing worktree/compose flows.

## Testing

Add or update pure grouping tests to cover:

- one folder receives sessions beneath its path;
- nested folders use the longest matching folder path;
- sessions outside every folder go to `Other`;
- Windows-style paths honor the injected path-platform setting;
- duplicate folder labels remain distinguishable.

Add focused sidebar widget tests to cover:

- `# 分组` is selected on first render;
- tapping `📁 项目树` switches views without changing the session data;
- manual groups remain visible only in the groups view;
- project nodes and their session tiles render in project-tree mode;
- project-node collapse hides and restores only that project's children;
- the `Other` node appears only when needed;
- worktree-specific header actions are absent from project-tree mode;
- existing global actions and session-tile activation continue to work.

All tests must follow the repository rule:

```bash
cd client && dart run tool/run_tests.dart <paths/options>
```

Before completion, run the required analyzer and full test commands from
`AGENTS.md`.

## Affected components

| Change | File |
| --- | --- |
| View enum, switcher placement, mode-specific rendering | `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` |
| Pure project-folder grouping projection | `client/lib/utils/session/session_project_grouping.dart` |
| Project node and child-session rendering | `client/lib/pages/home_workspace/workspace/project_tree_section.dart` |
| English and Chinese labels | `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` |
| Grouping unit tests | `client/test/utils/session/` |
| Sidebar behavior tests | `client/test/pages/home_workspace/workspace/` |
