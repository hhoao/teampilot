# Sidebar Groups and Project Tree Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the workspace sidebar into a default `# 分组` view and a `📁 项目树` view that groups conversations by project directory without exposing Git worktrees.

**Architecture:** Keep the change local to the workspace sidebar. Add a pure project-folder projection over existing `WorkspaceFolder` and `AppSession` data, render it with a focused stateful project-tree widget, and let the sidebar choose between the existing manual-group/flat-list composition and the new project tree. Leave `WorktreeCubit` and all worktree-aware launch behavior intact outside sidebar browsing.

**Tech Stack:** Flutter, Dart, `flutter_bloc`, `shared_ui` (`TpSegmentedControl`, `TpHoverRow`, `TpIconButton`), existing `ChatCubit`/`SessionGroupsCubit`, localized ARB resources, repository test runner.

## Global Constraints

- Never invoke `flutter test` directly; use `cd client && dart run tool/run_tests.dart <paths/options>`.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Preserve unrelated existing worktree and submodule changes; stage only files belonging to this feature in each commit.
- Use injected path-platform state (`homeStorageOf(context).usesPosixPaths`) and existing workspace path helpers; do not use `Directory.current`.
- Edit only `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` for localized copy; regenerate localization output instead of hand-editing generated files.
- Use existing `TpTextStyles` and shared-ui controls; do not add inline typography or a duplicate segmented-control primitive.
- Keep `WorktreeCubit` available for compose, launch, IDE, and runtime working-directory behavior; remove only sidebar worktree grouping presentation.
- Follow TDD for new behavior: write a focused failing test, run it through `tool/run_tests.dart`, implement the smallest passing change, then rerun the focused test.

## File Map

| File | Responsibility in this change |
| --- | --- |
| `client/lib/utils/session/session_project_grouping.dart` | Add the pure `ProjectSessionGroup` projection and longest-folder-prefix assignment. |
| `client/lib/pages/home_workspace/workspace/project_tree_section.dart` | Render collapsible project nodes and existing `SidebarSessionTile` children. |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | Own the default view, render the switcher, and remove worktree grouping from sidebar list construction. |
| `client/lib/l10n/app_en.arb` | Add English labels for the two sidebar views and the project-tree fallback node. |
| `client/lib/l10n/app_zh.arb` | Add Chinese labels for the two sidebar views and the project-tree fallback node. |
| `client/test/utils/session/session_project_grouping_test.dart` | Test project-folder assignment, nested paths, fallback, platform paths, and duplicate labels. |
| `client/test/pages/home_workspace/workspace/project_tree_section_test.dart` | Test project tree rendering and collapse behavior. |
| `client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart` | Verify default mode, mode switching, and manual-group visibility. |
| `client/test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart` | Remove obsolete worktree-section assumptions and cover the flat groups view/project tree behavior that replaces them. |

---

### Task 1: Add the pure project-folder grouping projection

**Files:**
- Modify: `client/lib/utils/session/session_project_grouping.dart`
- Test: `client/test/utils/session/session_project_grouping_test.dart`

**Interfaces:**
- Consumes: `List<WorkspaceFolder>`, `List<AppSession>`, and `usesPosixPaths`.
- Produces: `ProjectSessionGroup` and `groupSessionsByProject(...)` for the sidebar widget.

- [ ] **Step 1: Write the failing grouping tests**

Append a `groupSessionsByProject` group to the existing project-grouping test file:

```dart
group('groupSessionsByProject', () {
  test('keeps folder order and assigns sessions by project path', () {
    const folders = [
      WorkspaceFolder(path: '/repo-a'),
      WorkspaceFolder(path: '/repo-b'),
    ];
    final sessions = [
      AppSession(
        sessionId: 'a',
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/repo-a/lib')],
        createdAt: 1,
      ),
      AppSession(
        sessionId: 'b',
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/repo-b')],
        createdAt: 1,
      ),
    ];

    final groups = groupSessionsByProject(
      folders: folders,
      sessions: sessions,
      usesPosixPaths: true,
    );

    expect(groups.map((group) => group.projectPath), ['/repo-a', '/repo-b']);
    expect(groups[0].sessions.map((session) => session.sessionId), ['a']);
    expect(groups[1].sessions.map((session) => session.sessionId), ['b']);
    expect(groups.any((group) => group.isOther), isFalse);
  });

  test('uses the longest matching folder for nested projects', () {
    const folders = [
      WorkspaceFolder(path: '/repo'),
      WorkspaceFolder(path: '/repo/packages/client'),
    ];
    final session = AppSession(
      sessionId: 'nested',
      workspaceId: 'w1',
      folders: const [
        WorkspaceFolder(path: '/repo/packages/client/lib'),
      ],
      createdAt: 1,
    );

    final groups = groupSessionsByProject(
      folders: folders,
      sessions: [session],
      usesPosixPaths: true,
    );

    expect(groups[0].sessions, isEmpty);
    expect(groups[1].sessions.single.sessionId, 'nested');
  });

  test('adds Other only for sessions outside every folder', () {
    const folders = [WorkspaceFolder(path: '/repo')];
    final session = AppSession(
      sessionId: 'orphan',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/elsewhere')],
      createdAt: 1,
    );

    final groups = groupSessionsByProject(
      folders: folders,
      sessions: [session],
      usesPosixPaths: true,
    );

    expect(groups, hasLength(2));
    expect(groups.last.isOther, isTrue);
    expect(groups.last.projectPath, isNull);
    expect(groups.last.sessions.single.sessionId, 'orphan');
  });

  test('matches Windows-style paths when POSIX paths are disabled', () {
    const folders = [WorkspaceFolder(path: r'C:\repo')];
    final session = AppSession(
      sessionId: 'windows',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: r'C:\repo\src')],
      createdAt: 1,
    );

    final groups = groupSessionsByProject(
      folders: folders,
      sessions: [session],
      usesPosixPaths: false,
    );

    expect(groups.single.sessions.single.sessionId, 'windows');
  });

  test('disambiguates duplicate folder basenames', () {
    const folders = [
      WorkspaceFolder(path: '/team-a/huji'),
      WorkspaceFolder(path: '/team-b/huji'),
    ];

    final groups = groupSessionsByProject(
      folders: folders,
      sessions: const [],
      usesPosixPaths: true,
    );

    expect(groups.map((group) => group.label), ['team-a/huji', 'team-b/huji']);
  });
});
```

- [ ] **Step 2: Run the focused tests and confirm they fail**

```bash
cd client && dart run tool/run_tests.dart test/utils/session/session_project_grouping_test.dart
```

Expected: FAIL because `ProjectSessionGroup` and `groupSessionsByProject` do not exist yet.

- [ ] **Step 3: Implement the projection in `session_project_grouping.dart`**

Add `package:flutter/foundation.dart` and this immutable result type before
the existing ownership helpers:

```dart
@immutable
class ProjectSessionGroup {
  const ProjectSessionGroup({
    required this.projectPath,
    required this.label,
    required this.sessions,
    this.isOther = false,
  });

  final String? projectPath;
  final String label;
  final List<AppSession> sessions;
  final bool isOther;
}
```

Add `groupSessionsByProject` with this contract:

```dart
List<ProjectSessionGroup> groupSessionsByProject({
  required List<WorkspaceFolder> folders,
  required List<AppSession> sessions,
  required bool usesPosixPaths,
})
```

Implementation requirements:

1. Create one mutable session bucket for every folder, preserving `folders`
   order, including folders with no sessions.
2. For each session call `owningProjectFolderForSession` with
   `worktreesByProjectPath: null`; this selects the longest matching folder
   path and does not probe Git.
3. Resolve the returned owner path back to its original folder by
   `workspacePathsEqual` and append the session to that bucket. Preserve the
   input session order because the caller supplies already-sorted sessions.
4. Append one `ProjectSessionGroup` with `isOther: true` and `projectPath:
   null` only when unmatched sessions exist.
5. Build labels from the folder basename. When two normalized folder paths
   have the same basename, use the shortest suffix containing enough parent
   segments to make every label unique. For `/team-a/huji` and
   `/team-b/huji`, the labels must be `team-a/huji` and `team-b/huji`.
6. Return immutable session lists (`List.unmodifiable`) in each result.

- [ ] **Step 4: Rerun the focused tests**

Run the same command. Expected: all existing project-grouping tests and all new `groupSessionsByProject` tests PASS.

- [ ] **Step 5: Commit the pure projection**

```bash
git add client/lib/utils/session/session_project_grouping.dart client/test/utils/session/session_project_grouping_test.dart
git commit -m "feat: add project folder session grouping"
```

### Task 2: Build the collapsible project-tree section

**Files:**
- Create: `client/lib/pages/home_workspace/workspace/project_tree_section.dart`
- Create: `client/test/pages/home_workspace/workspace/project_tree_section_test.dart`

**Interfaces:**
- Consumes: `List<ProjectSessionGroup>`, `Workspace`, `tabScopeId`, and the active session id.
- Produces: `ProjectTreeSection`, a stateful `ListView.builder` with one project node per group.

- [ ] **Step 1: Write the failing widget tests**

Create a focused widget harness using the same storage and cubit setup as `workspace_sidebar_manual_groups_test.dart`. Use this test data and assertions:

```dart
final groups = [
  ProjectSessionGroup(
    projectPath: '/tmp/huji',
    label: 'huji',
    sessions: [_session('a', '/tmp/huji')],
  ),
  const ProjectSessionGroup(
    projectPath: null,
    label: '',
    sessions: [],
    isOther: true,
  ),
];

testWidgets('renders project nodes and session children', (tester) async {
  await pumpProjectTree(tester, groups);

  expect(find.text('huji'), findsOneWidget);
  expect(find.byType(SidebarSessionTile), findsOneWidget);
  expect(find.text('Other'), findsNothing);
});

testWidgets('collapsing a project hides only its children', (tester) async {
  await pumpProjectTree(tester, groups);

  await tester.tap(find.byKey(const ValueKey('project-tree-node-/tmp/huji')));
  await tester.pump();

  expect(find.text('huji'), findsOneWidget);
  expect(find.byType(SidebarSessionTile), findsNothing);
});

testWidgets('renders Other only when it has sessions', (tester) async {
  final withOther = [
    groups.first,
    ProjectSessionGroup(
      projectPath: null,
      label: '',
      sessions: [_session('orphan', '/tmp/elsewhere')],
      isOther: true,
    ),
  ];
  await pumpProjectTree(tester, withOther);

  expect(find.text('Other'), findsOneWidget);
  expect(find.byType(SidebarSessionTile), findsNWidgets(2));
});
```

The helper `_session(String id, String path)` must create an `AppSession` with the test workspace id and `WorkspaceFolder(path: path)` as its first folder.

- [ ] **Step 2: Run the widget tests and confirm they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/project_tree_section_test.dart
```

Expected: FAIL because `ProjectTreeSection` does not exist yet.

- [ ] **Step 3: Implement `ProjectTreeSection`**

Use this public constructor shape:

```dart
class ProjectTreeSection extends StatefulWidget {
  const ProjectTreeSection({
    required this.groups,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    super.key,
  });

  final List<ProjectSessionGroup> groups;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
}
```

Implementation requirements:

1. Keep a `Set<String> _collapsedPaths` in state. Use `'<project-orphan>'`
   for the Other node key.
2. Render groups with `ListView.builder`, `padding: EdgeInsets.zero`, and a
   stable node key `ValueKey('project-tree-node-${group.projectPath ?? '<project-orphan>'}')`.
3. Render each node with `TpHoverRow`, `kWorkspaceSidebarRowPadding`, and
   `workspaceSidebarRowHoverFill`. Use a folder icon at rest, a chevron while
   hovered, and `onTap` to toggle `_collapsedPaths`.
4. Resolve the display label as
   `group.isOther ? context.l10n.projectTreeOther : group.label`.
5. When expanded, render each group session with `SidebarSessionTile`, key
   `ValueKey('project-tree-session-${session.sessionId}')`, the passed active
   session id, and the existing `openWorkspaceSessionTab` callback. Do not
   add drag-reorder behavior to project-tree children.
6. Return `TpEmptyState(icon: Icons.forum_outlined, title: context.l10n.homeWorkspaceNoConversations, centered: true)` when there are no sessions and no non-empty project node. Do not manufacture an Other node in that case.
7. Do not read `WorktreeCubit` or render branch labels/actions.

- [ ] **Step 4: Run the focused widget tests**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/project_tree_section_test.dart
```

Expected: PASS for project-node rendering, collapse, and conditional Other rendering.

- [ ] **Step 5: Commit the project-tree widget**

```bash
git add client/lib/pages/home_workspace/workspace/project_tree_section.dart client/test/pages/home_workspace/workspace/project_tree_section_test.dart
git commit -m "feat: add collapsible project tree sidebar section"
```

### Task 3: Integrate the two sidebar views and remove worktree presentation

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart`
- Modify: `client/test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart`

**Interfaces:**
- Consumes: `groupSessionsByProject`, `ProjectTreeSection`, and the existing flat `SessionListStructure`.
- Produces: a sidebar whose initial mode is groups and whose mode switcher selects only groups or project tree.

- [ ] **Step 1: Add failing sidebar mode tests**

Extend the existing sidebar test harness with:

```dart
testWidgets('opens in groups mode', (tester) async {
  await pumpSidebar(tester);

  expect(find.byKey(const ValueKey('workspace-sidebar-view-switcher')), findsOneWidget);
  expect(find.text('Groups'), findsOneWidget);
  expect(find.text('Project tree'), findsOneWidget);
  expect(find.byTooltip('New group'), findsOneWidget);
});

testWidgets('switches to project tree without changing sessions', (tester) async {
  await pumpSidebar(tester);

  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
      matching: find.text('Project tree'),
    ),
  );
  await tester.pump();

  expect(find.text('huji'), findsOneWidget);
  expect(find.text('待办'), findsNothing);
  expect(find.byTooltip('New group'), findsNothing);
  expect(chatCubit.state.sessions, hasLength(2));
});

testWidgets('switching back restores manual groups', (tester) async {
  await pumpSidebar(tester);
  groupsCubit.createGroup('待办');
  await tester.pump();

  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
      matching: find.text('Project tree'),
    ),
  );
  await tester.pump();
  expect(find.text('待办'), findsNothing);

  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
      matching: find.text('Groups'),
    ),
  );
  await tester.pump();
  expect(find.text('待办'), findsOneWidget);
});
```

Use a workspace with `/tmp/huji` and session folders under `/tmp/huji` for project-tree assertions. Keep the existing tag-style assertion that a group member remains in the flat groups list.

In `workspace_sidebar_grouped_virtualization_test.dart`, remove assertions that require `WorktreeGroupSection`, worktree collapse keys, `More`/`Show less`, or multiple worktree-specific `ReorderableListView`s. Replace them with assertions that groups mode has one flat `ReorderableListView` and project-tree mode has project node keys with session children.

- [ ] **Step 2: Run the focused sidebar tests and confirm they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart
```

Expected: FAIL because the sidebar has no view enum, switcher keys, or project-tree branch.

- [ ] **Step 3: Add the local sidebar view state and switcher**

In `workspace_sidebar.dart`, add:

```dart
enum _WorkspaceSidebarView { groups, projectTree }
```

Initialize the state field as:

```dart
_WorkspaceSidebarView _view = _WorkspaceSidebarView.groups;
```

Use `TpSegmentedControl` in the conversation-section header:

```dart
TpSegmentedControl(
  key: const ValueKey('workspace-sidebar-view-switcher'),
  totalSwitches: 2,
  initialLabelIndex: _view == _WorkspaceSidebarView.groups ? 0 : 1,
  labels: [
    l10n.workspaceSidebarGroupsView,
    l10n.workspaceSidebarProjectTreeView,
  ],
  icons: const [Icons.tag_outlined, Icons.folder_outlined],
  tooltips: [
    l10n.workspaceSidebarGroupsView,
    l10n.workspaceSidebarProjectTreeView,
  ],
  onToggle: (index) {
    if (index == null) return;
    setState(() {
      _view = index == 0
          ? _WorkspaceSidebarView.groups
          : _WorkspaceSidebarView.projectTree;
    });
  },
)
```

Test the segments through text descendants of the keyed `TpSegmentedControl`; do not fork or modify the shared control merely to add test keys.

- [ ] **Step 4: Make groups mode flat and project-tree mode independent of Git**

Change `_ConversationListHost` to receive:

```dart
required _WorkspaceSidebarView view,
```

and pass `_view` from `WorkspaceSidebar`.

After building `sortedSessions` and applying the existing hydration skeleton, branch as follows:

```dart
if (view == _WorkspaceSidebarView.projectTree) {
  final projectGroups = groupSessionsByProject(
    folders: workspace.folders,
    sessions: sortedSessions,
    usesPosixPaths: homeStorageOf(context).usesPosixPaths,
  );
  return ProjectTreeSection(
    groups: projectGroups,
    workspace: workspace,
    tabScopeId: tabScopeId,
    highlightSessionId: scopedActiveSessionId(
      context.read<WorkbenchCubit>(),
      tabScopeId,
    ),
  );
}

return _buildWithManualGroups(
  context,
  _buildSessionList(context, structure.sessionIds),
);
```

Remove the `WorktreeCubit` selection, `WorktreeSidebarView` parameter, and the `_buildWorktreeGroupList` / `_buildMultiProjectWorktreeGroupedList` branches. Remove imports used only by the old sidebar worktree presentation, including `GitWorktree`, `GitWorktreeService`, `worktree_create_dialog.dart`, `session_worktree_grouping.dart`, and `worktree_group_section.dart`. Delete `_createWorktree` and its refresh/create header buttons. Keep `WorktreeCubit` providers in the outer workspace composition and all non-sidebar references.

The groups-mode header shows the new-group button only when `_view` is `groups`; sort and archive remain available in both modes. The existing top-level new-conversation, search, running-session, and footer management areas remain unchanged.

- [ ] **Step 5: Run the focused sidebar tests**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart test/pages/home_workspace/workspace/project_tree_section_test.dart
```

Expected: PASS with no worktree group headers, no worktree refresh/create controls, default groups mode, and working project-tree mode.

- [ ] **Step 6: Commit the sidebar integration**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_sidebar.dart client/test/pages/home_workspace/workspace/workspace_sidebar_manual_groups_test.dart client/test/pages/home_workspace/workspace_sidebar_grouped_virtualization_test.dart
git commit -m "feat: split sidebar groups and project tree views"
```

### Task 4: Add localized copy and complete verification

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify (generated): `client/lib/l10n/app_localizations.dart`, `client/lib/l10n/app_localizations_en.dart`, and `client/lib/l10n/app_localizations_zh.dart`; regenerate them and do not hand-edit them.

**Interfaces:**
- Consumes: the exact l10n getter names used by the switcher and project-tree widget.
- Produces: `workspaceSidebarGroupsView`, `workspaceSidebarProjectTreeView`, and `projectTreeOther` in both supported locales.

- [ ] **Step 1: Add the ARB entries**

Add these entries to `app_en.arb`:

```json
"workspaceSidebarGroupsView": "Groups",
"workspaceSidebarProjectTreeView": "Project tree",
"projectTreeOther": "Other",
```

Add these entries to `app_zh.arb`:

```json
"workspaceSidebarGroupsView": "分组",
"workspaceSidebarProjectTreeView": "项目树",
"projectTreeOther": "其他",
```

Keep existing worktree-specific l10n entries that are still used by compose and worktree dialogs.

- [ ] **Step 2: Regenerate localization output and analyze**

Run:

```bash
cd client && flutter gen-l10n
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: generation completes and analyzer reports no new errors or warnings.

- [ ] **Step 3: Run the complete repository test suite**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: the full suite passes. If an existing test still asserts a worktree-grouped sidebar layout, update only that assertion to the confirmed groups/project-tree behavior, rerun its focused file, and rerun the full suite.

- [ ] **Step 4: Inspect the final diff and worktree**

```bash
git diff --check
git diff --cached --check
git status --short
git diff --stat HEAD
```

Confirm that only feature commits contain the sidebar/project-tree files, ARB files, tests, and generated localization changes. Do not stage or modify the pre-existing submodule changes, plans, or specs.

- [ ] **Step 5: Commit localization and final test updates**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "feat: localize sidebar project tree"
```
