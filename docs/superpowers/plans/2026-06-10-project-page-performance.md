# Project Page Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce unnecessary rebuilds and repeated work on TeamPilot project list and project detail pages so scrolling, tab switching, and terminal workbench feel faster.

**Architecture:** Tackle optimizations in four independent PR-sized phases: (1) pure utils + cubit-derived indexes, (2) `ChatPage` granular `BlocSelector`/`context.select`, (3) home workspace list + sidebar scoped subscriptions, (4) project page layout keep-alive and local split state. Each phase ships working software and passes `flutter analyze` + `flutter test`.

**Tech Stack:** Flutter 3.x, `flutter_bloc`, `go_router`, existing cubits (`ChatCubit`, `ProjectProfileCubit`, `LayoutCubit`).

---

## File map

| File | Responsibility after plan |
|------|---------------------------|
| `client/lib/utils/project_sessions.dart` | O(n) `sessionsForProject`; new `groupSessionsByProjectId` |
| `client/lib/utils/home_workspace_project_display.dart` | **Create** — memoized sort + session counts for project grid/list |
| `client/lib/pages/chat/chat_page_shell.dart` | **Create** — `WorkspaceShell` wrapper with selective `ChatCubit` subscriptions |
| `client/lib/pages/chat_page.dart` | Thin route shell; delegates to `chat_page_shell.dart` |
| `client/lib/pages/home_workspace/home_workspace_projects_tab.dart` | Use display helper; stable `ValueKey` on list/grid items |
| `client/lib/pages/home_workspace/home_workspace_personal_content.dart` | Memoized personal project filter |
| `client/lib/pages/home_workspace/home_workspace_content.dart` | Memoized team project filter |
| `client/lib/pages/home_workspace/project/home_workspace_project_sidebar.dart` | Select sessions for one `projectId` only |
| `client/lib/pages/home_workspace/project/home_workspace_project_page.dart` | `IndexedStack` keep-alive; local split width widget |
| `client/lib/pages/home_workspace/project/home_workspace_project_split_pane.dart` | **Create** — split pane that does not rebuild parent on drag |
| `client/test/utils/project_sessions_test.dart` | New cases for orphan merge + grouping |
| `client/test/utils/home_workspace_project_display_test.dart` | **Create** — memoization + sort integration |
| `client/test/pages/chat_page_rebuild_test.dart` | **Create** — regression: `workingSessionIds` change does not rebuild shell marker |

**Out of scope (follow-up plan):** config-section `IndexedStack`, skeleton loaders, reducing `flutter_animate` on home tabs, `ChatState.projectsById` in cubit (only add if profiling shows list scan is hot).

**Reference docs:** [AGENTS.md](../../AGENTS.md), [docs/CODE_QUALITY.md](../CODE_QUALITY.md), [docs/DEVELOPMENT.md](../DEVELOPMENT.md).

**Verification (every phase):**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

---

## Phase 1 — Utils: session ordering and project display memo

### Task 1: Fix `sessionsForProject` orphan merge to O(n)

**Files:**
- Modify: `client/lib/utils/project_sessions.dart`
- Test: `client/test/utils/project_sessions_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `client/test/utils/project_sessions_test.dart`:

```dart
  test('sessionsForProject appends orphan sessions without duplicates', () {
    final project = AppProject(
      projectId: 'p1',
      primaryPath: '/tmp',
      sessionIds: const ['s1'],
      createdAt: 1,
    );
    final all = [
      session(id: 's1', projectId: 'p1', display: 'Listed'),
      session(id: 's2', projectId: 'p1', display: 'Orphan'),
      session(id: 's3', projectId: 'p2', display: 'Other'),
    ];

    final ordered = sessionsForProject(project, all);

    expect(ordered.map((s) => s.sessionId).toList(), ['s1', 's2']);
  });
```

- [ ] **Step 2: Run test to verify it passes on current code (baseline)**

Run: `cd client && flutter test test/utils/project_sessions_test.dart --name "appends orphan"`

Expected: PASS (documents current behavior before refactor).

- [ ] **Step 3: Refactor implementation**

Replace the orphan loop in `client/lib/utils/project_sessions.dart`:

```dart
List<AppSession> sessionsForProject(
  AppProject project,
  List<AppSession> all,
) {
  final byId = {for (final s in all) s.sessionId: s};
  final ordered = <AppSession>[];
  final seen = <String>{};
  for (final id in project.sessionIds) {
    final s = byId[id];
    if (s == null) continue;
    ordered.add(s);
    seen.add(id);
  }
  for (final s in all) {
    if (s.projectId != project.projectId) continue;
    if (seen.contains(s.sessionId)) continue;
    ordered.add(s);
    seen.add(s.sessionId);
  }
  return ordered;
}
```

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/utils/project_sessions_test.dart`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/project_sessions.dart client/test/utils/project_sessions_test.dart
git commit -m "perf: make sessionsForProject orphan merge O(n)"
```

---

### Task 2: Add `groupSessionsByProjectId`

**Files:**
- Modify: `client/lib/utils/project_sessions.dart`
- Test: `client/test/utils/project_sessions_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  test('groupSessionsByProjectId buckets sessions by projectId', () {
    final all = [
      session(id: 's1', projectId: 'p1'),
      session(id: 's2', projectId: 'p1'),
      session(id: 's3', projectId: 'p2'),
    ];

    final grouped = groupSessionsByProjectId(all);

    expect(grouped['p1']!.map((s) => s.sessionId).toList(), ['s1', 's2']);
    expect(grouped['p2']!.map((s) => s.sessionId).toList(), ['s3']);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/utils/project_sessions_test.dart --name "groupSessionsByProjectId"`

Expected: FAIL — `groupSessionsByProjectId` not defined.

- [ ] **Step 3: Implement**

Add to `client/lib/utils/project_sessions.dart`:

```dart
/// All [sessions] grouped by [AppSession.projectId]. Order within each bucket
/// matches [all] iteration order.
Map<String, List<AppSession>> groupSessionsByProjectId(
  List<AppSession> all,
) {
  final grouped = <String, List<AppSession>>{};
  for (final session in all) {
    final projectId = session.projectId;
    if (projectId.isEmpty) continue;
    grouped.putIfAbsent(projectId, () => []).add(session);
  }
  return grouped;
}
```

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/utils/project_sessions_test.dart`

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/project_sessions.dart client/test/utils/project_sessions_test.dart
git commit -m "feat: add groupSessionsByProjectId helper"
```

---

### Task 3: Memoized home workspace project display

**Files:**
- Create: `client/lib/utils/home_workspace_project_display.dart`
- Test: `client/test/utils/home_workspace_project_display_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/utils/home_workspace_project_display_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_project_sort.dart';
import 'package:teampilot/utils/home_workspace_project_display.dart';

void main() {
  AppProject project(String id, {int updatedAt = 0}) => AppProject(
        projectId: id,
        primaryPath: '/tmp/$id',
        createdAt: 1,
        updatedAt: updatedAt,
      );

  AppSession session(String id, String projectId) => AppSession(
        sessionId: id,
        projectId: projectId,
        primaryPath: '/tmp',
        createdAt: 1,
      );

  test('computeHomeWorkspaceProjectDisplay is stable when inputs unchanged', () {
    final projects = [project('a', updatedAt: 2), project('b', updatedAt: 1)];
    final sessions = [session('s1', 'a')];
    const favorites = <String>{};
    const sort = HomeWorkspaceProjectSort.recentlyUpdated;

    final first = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: sessions,
      sort: sort,
      favoriteProjectIds: favorites,
      displayName: (p) => p.projectId,
    );
    final second = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: sessions,
      sort: sort,
      favoriteProjectIds: favorites,
      displayName: (p) => p.projectId,
    );

    expect(identical(first.sortedProjects, second.sortedProjects), isTrue);
    expect(identical(first.sessionCounts, second.sessionCounts), isTrue);
    expect(first.sortedProjects.map((p) => p.projectId).toList(), ['a', 'b']);
    expect(first.sessionCounts['a'], 1);
  });

  test('computeHomeWorkspaceProjectDisplay recomputes when sessions change', () {
    final projects = [project('a')];
    const sort = HomeWorkspaceProjectSort.recentlyUpdated;

    final before = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: const [],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );
    final after = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: [session('s1', 'a')],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );

    expect(identical(before.sessionCounts, after.sessionCounts), isFalse);
    expect(after.sessionCounts['a'], 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/utils/home_workspace_project_display_test.dart`

Expected: FAIL — import / function not found.

- [ ] **Step 3: Implement**

Create `client/lib/utils/home_workspace_project_display.dart`:

```dart
import '../models/app_project.dart';
import '../models/app_session.dart';
import '../pages/home_workspace/home_workspace_project_sort.dart';

class HomeWorkspaceProjectDisplay {
  const HomeWorkspaceProjectDisplay({
    required this.sortedProjects,
    required this.sessionCounts,
  });

  final List<AppProject> sortedProjects;
  final Map<String, int> sessionCounts;
}

/// Sorts [projects] and counts sessions. Returns the previous [cached] result
/// when all inputs are unchanged (reference equality on lists/maps).
HomeWorkspaceProjectDisplay computeHomeWorkspaceProjectDisplay({
  required List<AppProject> projects,
  required List<AppSession> sessions,
  required HomeWorkspaceProjectSort sort,
  required Set<String> favoriteProjectIds,
  required String Function(AppProject project) displayName,
  HomeWorkspaceProjectDisplay? cached,
  List<AppProject>? lastProjects,
  List<AppSession>? lastSessions,
  HomeWorkspaceProjectSort? lastSort,
  Set<String>? lastFavorites,
}) {
  if (cached != null &&
      identical(projects, lastProjects) &&
      identical(sessions, lastSessions) &&
      sort == lastSort &&
      identical(favoriteProjectIds, lastFavorites)) {
    return cached;
  }

  final sessionCounts = homeWorkspaceSessionCountByProjectId(sessions);
  final sortedProjects = sortHomeWorkspaceProjects(
    projects: projects,
    sort: sort,
    favoriteProjectIds: favoriteProjectIds,
    sessionCountByProjectId: sessionCounts,
    displayName: displayName,
  );
  return HomeWorkspaceProjectDisplay(
    sortedProjects: sortedProjects,
    sessionCounts: sessionCounts,
  );
}
```

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/utils/home_workspace_project_display_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/home_workspace_project_display.dart client/test/utils/home_workspace_project_display_test.dart
git commit -m "perf: add memoized home workspace project display helper"
```

---

## Phase 2 — ChatPage: granular rebuild scope

### Task 4: Extract selective `ChatPageShell`

**Files:**
- Create: `client/lib/pages/chat/chat_page_shell.dart`
- Modify: `client/lib/pages/chat_page.dart`
- Test: `client/test/pages/chat_page_rebuild_test.dart`

- [ ] **Step 1: Write the failing rebuild regression test**

Create `client/test/pages/chat_page_rebuild_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/team_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat_page.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/team_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';

import '../support/post_frame_test_harness.dart';

class _ShellRebuildProbe extends StatefulWidget {
  const _ShellRebuildProbe({required this.child});
  final Widget child;
  static int buildCount = 0;

  @override
  State<_ShellRebuildProbe> createState() => _ShellRebuildProbeState();
}

class _ShellRebuildProbeState extends State<_ShellRebuildProbe> {
  @override
  Widget build(BuildContext context) {
    _ShellRebuildProbe.buildCount++;
    return widget.child;
  }
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    _ShellRebuildProbe.buildCount = 0;
  });

  tearDown(tearDownTestAppStorage);

  testWidgets('workingSessionIds update does not rebuild ChatPage shell probe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appData = Directory.systemTemp.createTempSync('chat_rebuild_test_');
    addTearDown(() => appData.deleteSync(recursive: true));

    final sessionRepo = SessionRepository(rootDir: appData.path);
    final chatCubit = ChatCubit(
      executableResolver: () => 'flashskyai',
      sessionRepository: sessionRepo,
    );
    addTearDown(chatCubit.close);

    final layoutCubit = LayoutCubit();
    addTearDown(layoutCubit.close);

    final editorCubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(editorCubit.close);

    final presenceCubit = MemberPresenceCubit();
    chatCubit.bindPresenceCubit(presenceCubit);
    addTearDown(presenceCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<SessionRepository>.value(
          value: sessionRepo,
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: chatCubit),
              BlocProvider.value(value: layoutCubit),
              BlocProvider.value(value: editorCubit),
              BlocProvider(
                create: (_) => TeamCubit(
                  repository: TeamRepository(rootDir: appData.path),
                  sessionRepository: sessionRepo,
                  reloadProjects: () async {},
                  executableResolver: () => 'flashskyai',
                  appDataBasePath: appData.path,
                  configProfileService:
                      ConfigProfileService(basePath: appData.path),
                ),
              ),
            ],
            child: const _ShellRebuildProbe(
              child: ChatPage(
                cwd: '/tmp',
                isPersonalProject: true,
                projectId: 'personal',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buildsAfterFirstFrame = _ShellRebuildProbe.buildCount;

    chatCubit.setWorkingSessionIds({'sess-1'});
    await tester.pump();

  expect(
      _ShellRebuildProbe.buildCount,
      buildsAfterFirstFrame,
      reason: 'ChatPage must not watch full ChatCubit for workingSessionIds',
    );
  });
}
```

Add `setWorkingSessionIds` only if the test cannot call an existing package-visible API — prefer using the existing package-visible method on `ChatCubit` (already exists at `chat_cubit.dart:143`). If the probe wraps the whole `ChatPage`, adjust the test to wrap only the shell tabs region after extraction (see Step 3).

- [ ] **Step 2: Run test — expect FAIL before refactor**

Run: `cd client && flutter test test/pages/chat_page_rebuild_test.dart`

Expected: FAIL — `buildCount` increases when `workingSessionIds` changes.

- [ ] **Step 3: Create `chat_page_shell.dart`**

Create `client/lib/pages/chat/chat_page_shell.dart` with:

1. `ChatPageShell` — owns layout preferences via `context.select<LayoutCubit, LayoutPreferences>((c) => c.state.preferences)`.
2. `_ChatWorkspaceShell` — `BlocSelector<ChatCubit, ChatState, _ShellTabModel>` selecting only `tabs`, `activeTabIndex`, `workingSessionIds`, `selectedMemberId` (team subtitle). Build `WorkspaceShell` inside the selector.
3. `ChatWorkbench` stays a direct child of `WorkspaceShell` (already has internal stream filter).

`_ShellTabModel` (private, bottom of file):

```dart
class _ShellTabModel {
  const _ShellTabModel({
    required this.tabs,
    required this.activeTabIndex,
    required this.workingSessionIds,
    required this.selectedMemberId,
  });

  final List<ChatTabInfo> tabs;
  final int activeTabIndex;
  final Set<String> workingSessionIds;
  final String selectedMemberId;

  @override
  bool operator ==(Object other) =>
      other is _ShellTabModel &&
      activeTabIndex == other.activeTabIndex &&
      selectedMemberId == other.selectedMemberId &&
      const SetEquality<String>().equals(
        workingSessionIds,
        other.workingSessionIds,
      ) &&
      const ListEquality<ChatTabInfo>().equals(tabs, other.tabs);

  @override
  int get hashCode => Object.hash(
        activeTabIndex,
        selectedMemberId,
        const SetEquality<String>().hash(workingSessionIds),
        const ListEquality<ChatTabInfo>().hash(tabs),
      );
}
```

Import `package:collection/collection.dart` for `ListEquality` / `SetEquality` (already a transitive Flutter dependency; add to `pubspec.yaml` under `dependencies` if analyzer requires explicit import).

Map tabs inside selector:

```dart
tabs: model.tabs
    .map(
      (t) => TabInfo(
        id: t.id,
        title: t.title,
        working: model.workingSessionIds.contains(t.id),
      ),
    )
    .toList(),
```

- [ ] **Step 4: Slim `chat_page.dart`**

Replace `_PersonalChatPage` / `_TeamChatPage` body to stop `context.watch<ChatCubit>()`. Pass `team` from `context.select<TeamCubit, TeamConfig?>` (team page only). Delegate shell construction to `ChatPageShell`.

Remove `chatCubit` parameter from `_ChatPageBody`; use `context.read<ChatCubit>()` in callbacks only.

- [ ] **Step 5: Run tests**

Run:

```bash
cd client
flutter test test/pages/chat_page_rebuild_test.dart
flutter test test/pages/chat_page_personal_test.dart
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat_page.dart client/lib/pages/chat/chat_page_shell.dart client/test/pages/chat_page_rebuild_test.dart
git commit -m "perf: narrow ChatPage rebuild scope with BlocSelector shell"
```

---

## Phase 3 — Home workspace list + project sidebar

### Task 5: Wire memoized display into project collection

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_projects_tab.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_personal_content.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_content.dart`

- [ ] **Step 1: Convert `HomeWorkspaceProjectCollection` to StatefulWidget**

In `home_workspace_projects_tab.dart`, change `HomeWorkspaceProjectCollection` to `StatefulWidget` with fields:

```dart
HomeWorkspaceProjectDisplay? _cached;
List<AppProject>? _lastProjects;
List<AppSession>? _lastSessions;
HomeWorkspaceProjectSort? _lastSort;
Set<String>? _lastFavorites;
```

In `build`, call `computeHomeWorkspaceProjectDisplay(...)` and pass `sorted` + `sessionCounts` to grid/list.

- [ ] **Step 2: Add stable keys to grid/list items**

In `HomeWorkspaceProjectGrid.itemBuilder`:

```dart
return HomeWorkspaceProjectCard(
  key: ValueKey('project-card-${project.projectId}'),
  ...
);
```

Same for `HomeWorkspaceProjectListTile` with `project-list-tile-`.

- [ ] **Step 3: Cache filtered project lists in personal/team content**

In `home_workspace_personal_content.dart`, add state fields `_lastAllProjects`, `_personalProjects`. In `build`:

```dart
final allProjects = context.select<ChatCubit, List<AppProject>>(
  (c) => c.state.projects,
);
final projects = identical(allProjects, _lastAllProjects)
    ? _personalProjects!
    : allProjects.where((p) => p.teamId.isEmpty).toList(growable: false);
if (!identical(allProjects, _lastAllProjects)) {
  _lastAllProjects = allProjects;
  _personalProjects = projects;
}
```

Mirror the same pattern in `home_workspace_content.dart` for `_projectsForTeam` using `team.id`.

- [ ] **Step 4: Run tests**

Run:

```bash
cd client
flutter test test/utils/home_workspace_project_display_test.dart
flutter test test/pages/home_workspace/home_workspace_project_sort_test.dart
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_projects_tab.dart \
        client/lib/pages/home_workspace/home_workspace_personal_content.dart \
        client/lib/pages/home_workspace/home_workspace_content.dart
git commit -m "perf: memoize project list sort and stable list keys"
```

---

### Task 6: Scope project sidebar session subscription

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_sidebar.dart`
- Test: `client/test/utils/project_sessions_test.dart` (already covered)

- [ ] **Step 1: Select grouped sessions for one project**

Replace the full-session `select` in `home_workspace_project_sidebar.dart`:

```dart
final sessions = context.select<ChatCubit, List<AppSession>>((c) {
  final grouped = groupSessionsByProjectId(c.state.sessions);
  final bucket = grouped[widget.project.projectId] ?? const <AppSession>[];
  return sessionsForProject(widget.project, bucket);
});
```

Because `select` uses `==`, ensure a stable empty list:

```dart
const _emptySessions = <AppSession>[];
// ...
final bucket = grouped[widget.project.projectId];
if (bucket == null || bucket.isEmpty) {
  return sessionsForProject(widget.project, _emptySessions);
}
return sessionsForProject(widget.project, bucket);
```

Add import: `import '../../../utils/project_sessions.dart';` (if not already).

- [ ] **Step 2: Add `ValueKey` on `SidebarSessionTile`**

```dart
return SidebarSessionTile(
  key: ValueKey('project-sidebar-session-${session.sessionId}'),
  ...
);
```

- [ ] **Step 3: Run analyze + existing widget tests**

Run:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/pages/home_workspace/project_isolation_widget_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/home_workspace_project_sidebar.dart
git commit -m "perf: scope project sidebar to per-project sessions"
```

---

## Phase 4 — Project detail page layout

### Task 7: Local split-pane width state (no page rebuild)

**Files:**
- Create: `client/lib/pages/home_workspace/project/home_workspace_project_split_pane.dart`
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart`
- Test: manual / widget smoke (no new unit test required — layout-only)

- [ ] **Step 1: Create split pane widget**

Create `client/lib/pages/home_workspace/project/home_workspace_project_split_pane.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../models/app_project.dart';
import '../../../models/layout_preferences.dart';
import '../../../widgets/resizable_split_view.dart';
import '../../chat_page.dart';
import 'home_workspace_project_sidebar.dart';

class HomeWorkspaceProjectSplitPane extends StatefulWidget {
  const HomeWorkspaceProjectSplitPane({
    required this.project,
    required this.isPersonalProject,
    super.key,
  });

  final AppProject project;
  final bool isPersonalProject;

  @override
  State<HomeWorkspaceProjectSplitPane> createState() =>
      _HomeWorkspaceProjectSplitPaneState();
}

class _HomeWorkspaceProjectSplitPaneState
    extends State<HomeWorkspaceProjectSplitPane> {
  double? _sidebarWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const minMain = LayoutPreferences.minWorkbenchMainWidth;
        const minSidebar = HomeWorkspaceProjectSidebarLayout.minWidth;
        const maxSidebarCap = HomeWorkspaceProjectSidebarLayout.maxWidth;
        final maxSidebar = (maxW - minMain).clamp(minSidebar, maxSidebarCap);
        final initialSidebar = (_sidebarWidth ??
                HomeWorkspaceProjectSidebarLayout.defaultWidth)
            .clamp(minSidebar, maxSidebar);
        return ResizableSplitView(
          first: HomeWorkspaceProjectSidebar(project: widget.project),
          second: ChatPage(
            cwd: widget.project.primaryPath,
            projectId: widget.project.projectId,
            isPersonalProject: widget.isPersonalProject,
          ),
          initialPrimarySize: initialSidebar,
          minPrimarySize: minSidebar,
          minSecondarySize: minMain,
          maxPrimarySize: maxSidebar,
          onPrimarySizeChanged: (width) => _sidebarWidth = width,
        );
      },
    );
  }
}
```

- [ ] **Step 2: Use split pane from project page**

In `home_workspace_project_page.dart`:
- Remove `_conversationSidebarWidth` field and `_buildConversationsWorkbench` body.
- Replace with `HomeWorkspaceProjectSplitPane(project: project, isPersonalProject: isPersonalProject)`.

- [ ] **Step 3: Run analyze + project isolation tests**

Run:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/pages/home_workspace/project_isolation_widget_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/home_workspace_project_split_pane.dart \
        client/lib/pages/home_workspace/project/home_workspace_project_page.dart
git commit -m "perf: isolate project split pane width state"
```

---

### Task 8: Keep conversation workbench alive across manage tab

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart`

- [ ] **Step 1: Add `IndexedStack` for personal project body**

Replace `_buildPersonalCardBody`:

```dart
Widget _buildPersonalCardBody(AppProject project) {
  final showManage = _section == HomeWorkspaceProjectSection.manage;
  return IndexedStack(
    index: showManage ? 1 : 0,
    sizing: StackFit.expand,
    children: [
      HomeWorkspaceProjectSplitPane(
        key: ValueKey('personal-conversations-${project.projectId}'),
        project: project,
        isPersonalProject: true,
      ),
      if (showManage || _visitedManage)
        HomeWorkspaceProjectConfigWorkspace(
          project: project,
          section: _configSection,
        )
      else
        const SizedBox.shrink(),
    ],
  );
}
```

Add state `var _visitedManage = false;` set to `true` in `_onSectionChanged` when section is `manage`, and in `initState` when route `view == 'manage'`.

- [ ] **Step 2: Manual check**

1. Open personal project → Conversations → start terminal.
2. Switch to Manage → back to Conversations.
3. Terminal session should still be connected (no full reconnect flash).

- [ ] **Step 3: Run full client tests**

Run: `cd client && flutter test --exclude-tags integration`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/home_workspace_project_page.dart
git commit -m "perf: keep personal project conversations alive in IndexedStack"
```

---

## Self-review

| Requirement from analysis | Task |
|---------------------------|------|
| ChatPage `watch` → selective rebuild | Task 4 |
| List sort/count memoization | Tasks 3, 5 |
| Sidebar per-project sessions | Task 6 |
| `sessionsForProject` O(n²) | Task 1 |
| Split drag local state | Task 7 |
| Conversations ↔ manage keep-alive | Task 8 |
| Config section lazy load / skeletons | Out of scope |
| Home tab animation reduction | Out of scope |
| `projectsById` on ChatState | Out of scope |

No TBD / placeholder steps remain. Types: `HomeWorkspaceProjectDisplay`, `_ShellTabModel`, `groupSessionsByProjectId` defined before use.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-10-project-page-performance.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Use superpowers:subagent-driven-development.

2. **Inline Execution** — run tasks in this session with superpowers:executing-plans, batch execution with checkpoints.

**Which approach?**
