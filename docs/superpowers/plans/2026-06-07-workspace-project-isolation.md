# Workspace Project-Level Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each open project hold its own keep-alive workspace runtime — isolated chat tabs, workspace terminal sessions, and right-tools selection keyed by `projectId` — so switching projects no longer leaks state across projects and restores each project's state on return.

**Architecture:** Direction B (project-keyed runtime). Keep the existing single-routed-child rendering. Three concerns become `projectId`-keyed: (1) `ChatTabStore` buckets tabs by project with an active-project pointer; (2) a new `WorkspaceTerminalRegistry` owns PTY sessions per project so they survive widget rebuilds; (3) a new `WorkspaceToolsCubit` holds the right-tools selected index per project. `HomeWorkspaceProjectPage` tells the cubit which project is active on switch; disposal happens when a project tab is closed.

**Tech Stack:** Flutter, `flutter_bloc` (cubits), `flutter_alacritty` terminal (`TerminalSession`/`TerminalController`), `flutter_test`/`bloc_test`.

**Spec:** `docs/superpowers/specs/2026-06-07-workspace-project-isolation-design.md`

**Branch:** `feat/workspace-project-isolation` (already created).

**Key design refinements over the spec (read before starting):**
- **Active-index handling has no per-operation mirroring.** `ChatState.activeTabIndex` stays the single source of truth for the *active* project while you work in it. `ChatTabStore` only *snapshots* the outgoing project's active index and *restores* the incoming project's when `setActiveProject` switches. This keeps churn in `chat_cubit.dart` / `session_launch_service.dart` near zero — those files keep calling `_tabStore.tabs`, `_tabStore.length`, `_tabStore.append`, etc., which now transparently operate on the active project's bucket.
- **`append` routes to the active project's bucket** and stamps `tab.projectId`. All session tabs are opened while their project page is active, so this is correct.
- **Terminal/tools panels are re-keyed by `projectId`** (was `cwd`). Their backing state lives in the registry/cubit, not the widget, so rebuilds re-attach instead of recreating.

**Verification command (run after each task's tests):**
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

---

## File Structure

**New files:**
- `client/lib/cubits/workspace_tools_cubit.dart` — per-project right-tools UI state (selected tool index). Small bloc cubit.
- `client/lib/services/terminal/workspace_terminal_registry.dart` — owns `Map<projectId, WorkspaceTerminalGroup>`; PTY sessions survive page rebuilds.
- `client/test/cubits/workspace_tools_cubit_test.dart`
- `client/test/services/terminal/workspace_terminal_registry_test.dart`
- `client/test/cubits/chat/chat_tab_store_bucketing_test.dart`
- `client/test/cubits/chat_cubit_project_scope_test.dart`
- `client/test/pages/home_workspace/project_isolation_widget_test.dart`

**Modified files:**
- `client/lib/cubits/chat/model/chat_tab.dart` — add `projectId` field.
- `client/lib/cubits/chat/chat_tab_store.dart` — bucket tabs by `projectId`.
- `client/lib/cubits/chat_cubit.dart` — add `setActiveProject`; route `closeTabsForProject`/`openTabCountForProject` through buckets.
- `client/lib/cubits/chat/session_launch_service.dart` — stamp `projectId` on tabs at creation.
- `client/lib/widgets/workspace_terminal_panel.dart` — read/write the registry, keyed by `projectId`.
- `client/lib/pages/workspace_shell/workspace_shell.dart` — thread `projectId` to the terminal panel.
- `client/lib/pages/workspace_shell/workspace_shell_layout.dart` — re-key terminal panel by `projectId`; pass it down.
- `client/lib/widgets/right_tools/tabbed_panel.dart` — optional `scopeId` to persist selection in `WorkspaceToolsCubit`.
- `client/lib/widgets/right_tools/right_tools_panel.dart` — thread `projectId`/`scopeId`.
- `client/lib/pages/chat_page.dart` — accept and thread `projectId`.
- `client/lib/pages/home_workspace/project/home_workspace_project_page.dart` — call `setActiveProject` on switch; pass `projectId` to `ChatPage`.
- `client/lib/pages/home_workspace/home_workspace_shell.dart` — dispose terminal group + tools state on close.
- `client/lib/app/app_shell.dart` — construct + expose `WorkspaceTerminalRegistry` and `WorkspaceToolsCubit`.
- `client/lib/main.dart` — provide them to the widget tree.

---

## Phase 0 — Right-tools selection per project (`WorkspaceToolsCubit`)

Smallest, fully self-contained slice. Replaces `_TabbedPanelState._selected` local state with a project-keyed cubit.

### Task 0.1: Create `WorkspaceToolsCubit`

**Files:**
- Create: `client/lib/cubits/workspace_tools_cubit.dart`
- Test: `client/test/cubits/workspace_tools_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/workspace_tools_cubit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';

void main() {
  group('WorkspaceToolsCubit', () {
    test('defaults a project to selected index 0', () {
      final cubit = WorkspaceToolsCubit();
      expect(cubit.selectedIndexFor('p1'), 0);
      addTearDown(cubit.close);
    });

    test('remembers a per-project selected index', () {
      final cubit = WorkspaceToolsCubit();
      cubit.setSelectedIndex('p1', 2);
      cubit.setSelectedIndex('p2', 1);
      expect(cubit.selectedIndexFor('p1'), 2);
      expect(cubit.selectedIndexFor('p2'), 1);
      expect(cubit.selectedIndexFor('p3'), 0);
      addTearDown(cubit.close);
    });

    test('emits a new state when a selection changes', () {
      final cubit = WorkspaceToolsCubit();
      final seen = <Map<String, int>>[];
      final sub = cubit.stream.listen((s) => seen.add(Map.of(s.selectedByProject)));
      cubit.setSelectedIndex('p1', 3);
      cubit.setSelectedIndex('p1', 3); // no-op, same value
      return Future<void>.delayed(Duration.zero, () {
        expect(seen.length, 1);
        expect(seen.single['p1'], 3);
        sub.cancel();
        cubit.close();
      });
    });

    test('removeProject drops the stored selection', () {
      final cubit = WorkspaceToolsCubit();
      cubit.setSelectedIndex('p1', 2);
      cubit.removeProject('p1');
      expect(cubit.selectedIndexFor('p1'), 0);
      addTearDown(cubit.close);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/workspace_tools_cubit_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/cubits/workspace_tools_cubit.dart'`.

- [ ] **Step 3: Write the implementation**

Create `client/lib/cubits/workspace_tools_cubit.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Per-project right-tools UI state (which tool tab is selected). Keyed by
/// `projectId` so each open project remembers its own selection across project
/// switches. Panel width/visibility stay global in [LayoutCubit] — this cubit
/// only owns the selected-tool index.
class WorkspaceToolsState extends Equatable {
  const WorkspaceToolsState({this.selectedByProject = const {}});

  final Map<String, int> selectedByProject;

  WorkspaceToolsState copyWith({Map<String, int>? selectedByProject}) =>
      WorkspaceToolsState(
        selectedByProject: selectedByProject ?? this.selectedByProject,
      );

  @override
  List<Object?> get props => [selectedByProject];
}

class WorkspaceToolsCubit extends Cubit<WorkspaceToolsState> {
  WorkspaceToolsCubit() : super(const WorkspaceToolsState());

  int selectedIndexFor(String projectId) =>
      state.selectedByProject[projectId] ?? 0;

  void setSelectedIndex(String projectId, int index) {
    if (selectedIndexFor(projectId) == index) return;
    final next = Map<String, int>.of(state.selectedByProject)
      ..[projectId] = index;
    emit(state.copyWith(selectedByProject: next));
  }

  void removeProject(String projectId) {
    if (!state.selectedByProject.containsKey(projectId)) return;
    final next = Map<String, int>.of(state.selectedByProject)
      ..remove(projectId);
    emit(state.copyWith(selectedByProject: next));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/workspace_tools_cubit_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/workspace_tools_cubit.dart client/test/cubits/workspace_tools_cubit_test.dart
git commit -m "feat(workspace): add WorkspaceToolsCubit for per-project tool selection"
```

### Task 0.2: Wire `WorkspaceToolsCubit` into DI and the widget tree

**Files:**
- Modify: `client/lib/app/app_shell.dart` (field + constructor + construction site)
- Modify: `client/lib/main.dart:183-203` (add `BlocProvider.value`)

- [ ] **Step 1: Add the field and constructor param to `AppShell`**

In `client/lib/app/app_shell.dart`, add to the constructor parameter list (near `required this.layoutCubit,` around line 95-110 — match the existing `required this.<name>,` style) :

```dart
    required this.workspaceToolsCubit,
```

And add the field next to `final LayoutCubit layoutCubit;` (line 130):

```dart
  final WorkspaceToolsCubit workspaceToolsCubit;
```

Add the import at the top of `app_shell.dart` (with the other cubit imports):

```dart
import '../cubits/workspace_tools_cubit.dart';
```

- [ ] **Step 2: Construct it in `buildAppShell`**

In `buildAppShell`, near where `layoutCubit` is constructed (`final layoutCubit = LayoutCubit(...)` around line 498), add:

```dart
  final workspaceToolsCubit = WorkspaceToolsCubit();
```

Then add `workspaceToolsCubit: workspaceToolsCubit,` to the `AppShell(...)` return constructor call (find the `return AppShell(` / `AppShell(` invocation that lists `layoutCubit: layoutCubit,` and add the new arg alongside it).

- [ ] **Step 3: Provide it in `main.dart`**

In `client/lib/main.dart`, add to the `MultiBlocProvider.providers` list (after line 193 `BlocProvider.value(value: shell.layoutCubit),`):

```dart
                BlocProvider.value(value: shell.workspaceToolsCubit),
```

- [ ] **Step 4: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart`
Expected: No errors (warnings about unused are acceptable only if pre-existing).

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(workspace): provide WorkspaceToolsCubit to the widget tree"
```

### Task 0.3: Make `TabbedPanel` use `WorkspaceToolsCubit` when scoped

**Files:**
- Modify: `client/lib/widgets/right_tools/tabbed_panel.dart`
- Modify: `client/lib/widgets/right_tools/right_tools_panel.dart:25-49, 181`
- Modify: `client/lib/pages/chat_page.dart` (pass `projectId` to `RightToolsPanel`)
- Test: covered by the widget test in Phase 4 (Task 4.1).

Backward compatible: when `scopeId` is null, `TabbedPanel` keeps its local-state behavior so any other call sites are unaffected.

- [ ] **Step 1: Add `scopeId` to `TabbedPanel` and read/write the cubit**

Replace the whole `TabbedPanel` + `_TabbedPanelState` (lines 9-54 of `tabbed_panel.dart`) with:

```dart
class TabbedPanel extends StatefulWidget {
  const TabbedPanel({required this.views, this.scopeId, super.key});

  final List<ToolView> views;

  /// When set, the selected tool index is persisted per-scope in
  /// [WorkspaceToolsCubit] (one scope == one projectId) so it survives project
  /// switches. When null, selection is local widget state.
  final String? scopeId;

  @override
  State<TabbedPanel> createState() => _TabbedPanelState();
}

class _TabbedPanelState extends State<TabbedPanel> {
  int _localSelected = 0;

  int _selectedIndex() {
    final scope = widget.scopeId;
    if (scope == null) return _localSelected;
    return context.read<WorkspaceToolsCubit>().selectedIndexFor(scope);
  }

  void _select(int index) {
    final scope = widget.scopeId;
    if (scope == null) {
      setState(() => _localSelected = index);
    } else {
      context.read<WorkspaceToolsCubit>().setSelectedIndex(scope, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.views.isEmpty) return const SizedBox.shrink();
    if (widget.views.length == 1) return widget.views.single.child;
    // Rebuild on cubit changes when scoped so the selection reflects the store.
    if (widget.scopeId != null) {
      context.watch<WorkspaceToolsCubit>();
    }
    final selected = _selectedIndex().clamp(0, widget.views.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              for (var i = 0; i < widget.views.length; i++)
                _SwitcherButton(
                  view: widget.views[i],
                  active: i == selected,
                  onTap: () => _select(i),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: selected,
            sizing: StackFit.expand,
            children: [for (final v in widget.views) v.child],
          ),
        ),
      ],
    );
  }
}
```

Add the imports at the top of `tabbed_panel.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/workspace_tools_cubit.dart';
```

- [ ] **Step 2: Thread `scopeId` from `RightToolsPanel`**

In `client/lib/widgets/right_tools/right_tools_panel.dart`, add a `projectId` param to the constructor (after `this.isPersonalProject = false,` at line 31):

```dart
    this.projectId,
```

And the field (after the `cwd` field, around line 45):

```dart
  /// Project this tools panel belongs to; scopes per-project UI state
  /// (selected tool tab). Null on routes without a project context.
  final String? projectId;
```

Then at line 181 change:

```dart
          ? TabbedPanel(views: views)
```

to:

```dart
          ? TabbedPanel(views: views, scopeId: widget.projectId)
```

- [ ] **Step 3: Pass `projectId` from `ChatPage`**

This depends on `ChatPage` exposing `projectId`, added in Task 3.1. For now leave `RightToolsPanel(... )` calls in `chat_page.dart` unchanged — they will be updated in Task 3.1 Step 3. (Scoped selection becomes active once `projectId` is threaded; until then `scopeId` is null and behavior is unchanged.)

- [ ] **Step 4: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/right_tools/tabbed_panel.dart lib/widgets/right_tools/right_tools_panel.dart`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/right_tools/tabbed_panel.dart client/lib/widgets/right_tools/right_tools_panel.dart
git commit -m "feat(workspace): scope right-tools selection per project in TabbedPanel"
```

---

## Phase 1 — Chat tabs bucketed by project (`ChatTabStore`)

This is the core data-layer change. After this phase, `ChatTabStore` keeps the same public method surface but every query/mutation operates on the *active project's* bucket. The cubit/launch-service call sites are unchanged except where noted.

### Task 1.1: Add `projectId` to `ChatTab`

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_tab.dart:12-16`
- Test: covered by Task 1.2's store tests.

- [ ] **Step 1: Add the field**

In `client/lib/cubits/chat/model/chat_tab.dart`, change the constructor (lines 12-16) to:

```dart
  ChatTab({
    required this.info,
    required this.cliTeamName,
    this.selectedMemberId = '',
    this.projectId = '',
  });
```

And add the field after `String selectedMemberId;` (line 20):

```dart
  /// Owning project bucket in [ChatTabStore]. Empty for legacy/local scratch
  /// tabs created without a project context.
  String projectId;
```

- [ ] **Step 2: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/cubits/chat/model/chat_tab.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/cubits/chat/model/chat_tab.dart
git commit -m "feat(chat): add projectId to ChatTab"
```

### Task 1.2: Bucket `ChatTabStore` by project

**Files:**
- Modify: `client/lib/cubits/chat/chat_tab_store.dart` (full rewrite of the storage internals; keep the helper methods `defaultMemberId`, `localSessionInfo`, `appendLocalTab`, `workingDirectoryAndAddDirsForTab`, `sessionForTab` behavior identical)
- Test: `client/test/cubits/chat/chat_tab_store_bucketing_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/chat/chat_tab_store_bucketing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  group('ChatTabStore bucketing', () {
    test('append routes tabs to the active project bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.setActiveProject('B');
      store.append(_tab('b1'));

      expect(store.length, 1);
      expect(store.tabs.single.info.id, 'b1');

      final restoredA = store.setActiveProject('A');
      expect(store.length, 2);
      expect(store.tabs.map((t) => t.info.id), ['a1', 'a2']);
      // A had no saved active index yet -> 0.
      expect(restoredA, 0);
    });

    test('append stamps the tab projectId', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      final tab = _tab('a1');
      store.append(tab);
      expect(tab.projectId, 'A');
    });

    test('setActiveProject snapshots and restores the active index', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      store.append(_tab('a3'));
      // Working in A, user is on index 2; snapshot it on the way out.
      store.setActiveProject('B', currentActiveIndex: 2);
      store.append(_tab('b1'));
      final restored = store.setActiveProject('A', currentActiveIndex: 0);
      expect(restored, 2);
    });

    test('removeProject returns and clears a bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.append(_tab('a2'));
      final removed = store.removeProject('A');
      expect(removed.map((t) => t.info.id), ['a1', 'a2']);
      // Active bucket is now empty.
      store.setActiveProject('A');
      expect(store.isEmpty, isTrue);
    });

    test('sessionBackedCountForProject ignores local scratch tabs', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('sess-1'));
      store.append(_tab('local-team1'));
      expect(store.sessionBackedCountForProject('A'), 1);
    });

    test('indexOfSession and bySessionId scope to the active bucket', () {
      final store = ChatTabStore();
      store.setActiveProject('A');
      store.append(_tab('a1'));
      store.setActiveProject('B');
      store.append(_tab('b1'));
      expect(store.indexOfSession('a1'), -1);
      expect(store.indexOfSession('b1'), 0);
      expect(store.bySessionId('a1'), isNull);
      expect(store.bySessionId('b1')?.info.id, 'b1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat/chat_tab_store_bucketing_test.dart`
Expected: FAIL — `setActiveProject`/`removeProject`/`sessionBackedCountForProject` not defined.

- [ ] **Step 3: Rewrite `ChatTabStore`**

Replace the entire contents of `client/lib/cubits/chat/chat_tab_store.dart` with:

```dart
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Owns the open-tab list and all pure queries/derivations over it.
/// Never emits — callers read results and update ChatState themselves.
///
/// Tabs are bucketed by `projectId`. Every query/mutation below operates on the
/// *active* project's bucket ([setActiveProject]); callers keep using the same
/// flat-list API. Per-project active-tab index is snapshotted on project switch,
/// not mirrored on every selection, so cubit call sites stay unchanged.
class ChatTabStore {
  final Map<String, List<ChatTab>> _byProject = {};
  final Map<String, int> _savedActiveIndex = {};
  String _activeProjectId = '';

  List<ChatTab> get _active => _byProject.putIfAbsent(_activeProjectId, () => []);

  /// Switches the active bucket. Pass [currentActiveIndex] (the cubit's current
  /// `ChatState.activeTabIndex`) to snapshot the outgoing project's selection.
  /// Returns the restored active-tab index for the incoming project (clamped).
  int setActiveProject(String projectId, {int? currentActiveIndex}) {
    if (currentActiveIndex != null && _activeProjectId.isNotEmpty) {
      _savedActiveIndex[_activeProjectId] = currentActiveIndex;
    }
    _activeProjectId = projectId;
    _byProject.putIfAbsent(projectId, () => []);
    final saved = _savedActiveIndex[projectId] ?? 0;
    final len = _byProject[projectId]!.length;
    if (len == 0) return 0;
    return saved.clamp(0, len - 1);
  }

  String get activeProjectId => _activeProjectId;

  List<ChatTab> get tabs => _active;
  int get length => _active.length;
  bool get isEmpty => _active.isEmpty;

  /// Clears every bucket (used on cubit close).
  void clear() {
    _byProject.clear();
    _savedActiveIndex.clear();
  }

  /// Removes and returns a project's bucket (for disposal by the caller).
  List<ChatTab> removeProject(String projectId) {
    _savedActiveIndex.remove(projectId);
    final removed = _byProject.remove(projectId) ?? const [];
    return List<ChatTab>.of(removed);
  }

  /// Session-backed (non-`local-`) tab count for [projectId], across any bucket.
  int sessionBackedCountForProject(String projectId) {
    final bucket = _byProject[projectId];
    if (bucket == null) return 0;
    return bucket.where((t) => !t.info.id.startsWith('local-')).length;
  }

  List<ChatTabInfo> toInfos() => _active.map((t) => t.info).toList();

  ChatTab? activeTab(int activeTabIndex) {
    if (_active.isEmpty) return null;
    final index = activeTabIndex.clamp(0, _active.length - 1);
    return _active[index];
  }

  ChatTab? bySessionId(String id) {
    for (final tab in _active) {
      if (tab.info.id == id) return tab;
    }
    return null;
  }

  int indexOfSession(String id) => _active.indexWhere((t) => t.info.id == id);

  void append(ChatTab tab) {
    tab.projectId = _activeProjectId;
    _active.add(tab);
  }

  ChatTab removeAt(int index) => _active.removeAt(index);

  String defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamConfig team) => ChatTabInfo(
    id: 'local-${team.id}',
    title: team.name,
    subtitle: 'local session',
  );

  ChatTab appendLocalTab(TeamConfig team, {required String cliTeamName}) {
    final tab = ChatTab(
      info: localSessionInfo(team),
      cliTeamName: cliTeamName,
      selectedMemberId: defaultMemberId(team),
      projectId: _activeProjectId,
    );
    _active.add(tab);
    return tab;
  }

  (String, List<String>) workingDirectoryAndAddDirsForTab(
    ChatTab tab,
    List<AppSession> sessions,
  ) {
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in sessions) {
      if (s.sessionId != tabId) continue;
      final wd = s.primaryPath.trim();
      final addl = s.additionalPaths
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (wd.isNotEmpty) {
        return (wd, addl);
      }
      return (AppStorage.cwd, addl);
    }
    return (AppStorage.cwd, const <String>[]);
  }

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }

  /// Every tab across all buckets (used on cubit close to dispose sessions).
  Iterable<ChatTab> get allTabs sync* {
    for (final bucket in _byProject.values) {
      yield* bucket;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/chat/chat_tab_store_bucketing_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/chat_tab_store.dart client/test/cubits/chat/chat_tab_store_bucketing_test.dart
git commit -m "feat(chat): bucket ChatTabStore tabs by projectId"
```

### Task 1.3: Update `ChatCubit` for buckets (`setActiveProject`, close-by-project, close())

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart` (add `setActiveProject`; rewrite `_tabIndicesForProject`→bucket count; rewrite `closeTabsForProject`; fix `close()` to dispose all buckets)
- Test: `client/test/cubits/chat_cubit_project_scope_test.dart`

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/chat_cubit_project_scope_test.dart`. This uses the existing test harness pattern — construct a `ChatCubit` with no repo and exercise the project-scoping facade directly via the tab store (no terminal launch).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatCubit _cubit() => ChatCubit(executableResolver: () => '/bin/true');

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  group('ChatCubit project scoping', () {
    test('setActiveProject swaps the visible tab list', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      // Mirror into state the way the launch flow does:
      cubit.refreshActiveProjectTabs();
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);

      cubit.setActiveProject('B');
      expect(cubit.state.tabs, isEmpty);

      cubit.setActiveProject('A');
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);
      addTearDown(cubit.close);
    });

    test('switching projects preserves each project active index', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.append(_tab('a3'));
      cubit.refreshActiveProjectTabs();
      cubit.selectTab(2);
      expect(cubit.state.activeTabIndex, 2);

      cubit.setActiveProject('B');
      cubit.setActiveProject('A');
      expect(cubit.state.activeTabIndex, 2);
      addTearDown(cubit.close);
    });

    test('openTabCountForProject counts only session tabs in that bucket', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('sess-1'));
      cubit.tabStore.append(_tab('local-team'));
      cubit.setActiveProject('B');
      cubit.tabStore.append(_tab('sess-2'));
      expect(cubit.openTabCountForProject('A'), 1);
      expect(cubit.openTabCountForProject('B'), 1);
      addTearDown(cubit.close);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat_cubit_project_scope_test.dart`
Expected: FAIL — `setActiveProject` / `refreshActiveProjectTabs` not defined on `ChatCubit`.

- [ ] **Step 3: Add `setActiveProject` + `refreshActiveProjectTabs` to `ChatCubit`**

In `client/lib/cubits/chat_cubit.dart`, add these methods right after `_pushPresenceTarget()` (after line 149):

```dart
  /// Switches the active project bucket and republishes its tabs into state.
  /// Called by the project page whenever the active project changes.
  void setActiveProject(String projectId) {
    final restoredIndex = _tabStore.setActiveProject(
      projectId,
      currentActiveIndex: state.activeTabIndex,
    );
    _publishActiveProjectTabs(restoredIndex);
  }

  /// Re-emits the active bucket's tab infos without changing the project.
  /// Used by the launch flow after it mutates the active bucket.
  void refreshActiveProjectTabs() =>
      _publishActiveProjectTabs(state.activeTabIndex);

  void _publishActiveProjectTabs(int desiredIndex) {
    if (_tabStore.isEmpty) {
      emit(
        state.copyWith(
          tabs: const [],
          activeTabIndex: 0,
          clearActiveSessionId: true,
          selectedMemberId: '',
        ),
      );
      _pushPresenceTarget();
      return;
    }
    final index = desiredIndex.clamp(0, _tabStore.length - 1);
    final tab = _tabStore.tabs[index];
    emit(
      state.copyWith(
        tabs: _tabStore.toInfos(),
        activeTabIndex: index,
        activeSessionId: tab.info.id,
        selectedMemberId: tab.selectedMemberId,
      ),
    );
    _pushPresenceTarget();
  }
```

- [ ] **Step 4: Rewrite `closeTabsForProject` / `openTabCountForProject` to use buckets**

Replace the block at lines 438-465 (`_tabIndicesForProject`, `openTabCountForProject`, `closeTabsForProject`) with:

```dart
  /// Number of open session-backed tabs in [projectId]'s bucket (excludes
  /// `local-` scratch tabs, which have no persisted project session).
  int openTabCountForProject(String projectId) =>
      _tabStore.sessionBackedCountForProject(projectId);

  /// Closes (terminates) every open tab belonging to [projectId] by dropping
  /// its whole bucket and disposing each tab's sessions and team-bus.
  void closeTabsForProject(String projectId) {
    final removed = _tabStore.removeProject(projectId);
    if (removed.isEmpty) return;
    for (final tab in removed) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _busCoordinator.maybeStopIdleWatch();
    if (projectId == _tabStore.activeProjectId) {
      _publishActiveProjectTabs(0);
    }
  }
```

- [ ] **Step 5: Fix `close()` to dispose all buckets**

In `close()` (lines 717-730), change the disposal loop from `_tabStore.tabs` to `_tabStore.allTabs`:

```dart
  @override
  Future<void> close() async {
    if (isClosed) return;
    _busCoordinator.disposeIdleWatch();
    for (final tab in _tabStore.allTabs) {
      for (final session in tab.sessions) {
        session.dispose();
      }
      // ignore: discarded_futures
      tab.disposeBus();
    }
    _tabStore.clear();
    await super.close();
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd client && flutter test test/cubits/chat_cubit_project_scope_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 7: Run the full chat test suite for regressions**

Run: `cd client && flutter test test/cubits/`
Expected: PASS (existing ChatCubit tests still green; if any pre-existing test constructed tabs without calling `setActiveProject`, the empty-string default bucket keeps them working).

- [ ] **Step 8: Commit**

```bash
git add client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_project_scope_test.dart
git commit -m "feat(chat): add project-scoped active bucket + close-by-project to ChatCubit"
```

### Task 1.4: Refresh tabs after the launch flow appends

The launch service calls `_h.applyState(... tabs: [..._state.tabs, info] ...)`. With buckets, `_state.tabs` already reflects the active bucket, so appends keep working. The one gap: ensure `setActiveProject` is invoked before any tab is opened (done in Phase 3, Task 3.2). No code change is needed in `session_launch_service.dart` because `append` stamps `projectId = activeProjectId` and the existing `applyState` calls already publish the active bucket's infos.

- [ ] **Step 1: Confirm no change needed by reading the call sites**

Read `client/lib/cubits/chat/session_launch_service.dart` lines 147-155 and 832-845. Verify each `applyState` after `_tabStore.append` / `appendLocalTab` sets `tabs:` from `_state.tabs` or `_tabStore.toInfos()` (both already bucket-scoped). No edit.

- [ ] **Step 2: Commit (noop marker)**

No commit — this task only verifies. Proceed to Phase 2.

---

## Phase 2 — Workspace terminal per project (`WorkspaceTerminalRegistry`)

Move the terminal tab list out of `_WorkspaceTerminalPanelState` into a registry keyed by `projectId` so PTYs and scrollback survive project switches.

### Task 2.1: Create `WorkspaceTerminalRegistry`

**Files:**
- Create: `client/lib/services/terminal/workspace_terminal_registry.dart`
- Test: `client/test/services/terminal/workspace_terminal_registry_test.dart`

The registry owns the data; it does **not** start PTYs (the panel drives connect/theme, which need `BuildContext`). It exposes per-project groups of `WorkspaceTerminalEntry` (id + cwd + session + controller + connected flag).

- [ ] **Step 1: Write the failing test**

Create `client/test/services/terminal/workspace_terminal_registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceTerminalRegistry', () {
    test('groupFor lazily creates and reuses a group per project', () {
      final reg = WorkspaceTerminalRegistry();
      final a1 = reg.groupFor('A');
      final a2 = reg.groupFor('A');
      final b1 = reg.groupFor('B');
      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b1), isFalse);
      reg.disposeAll();
    });

    test('addEntry / entries stays scoped to its project group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(cwd: '/tmp/a', select: true);
      expect(a.entries.single, entry);
      expect(a.activeId, entry.id);
      expect(reg.groupFor('B').entries, isEmpty);
      reg.disposeAll();
    });

    test('disposeProject disposes entries and drops the group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(cwd: '/tmp/a', select: true);
      reg.disposeProject('A');
      // Disposing the session twice must be safe.
      expect(entry.session.isRunning, isFalse);
      // A fresh group is created on next access (entries empty).
      expect(reg.groupFor('A').entries, isEmpty);
      reg.disposeAll();
    });

    test('removeEntry reselects the active id', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final e1 = a.addEntry(cwd: '/tmp/a', select: true);
      final e2 = a.addEntry(cwd: '/tmp/a2', select: true);
      expect(a.activeId, e2.id);
      a.removeEntry(e2.id);
      expect(a.activeId, e1.id);
      expect(a.entries.single, e1);
      reg.disposeAll();
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/terminal/workspace_terminal_registry_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/terminal/workspace_terminal_registry.dart`:

```dart
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'terminal_session.dart';
import 'workspace_interactive_shell.dart';

const _uuid = Uuid();

/// A single workspace-terminal tab's runtime: its shell session, the view
/// controller (kept alive across widget rebuilds to preserve scroll/selection),
/// its working directory, and whether a connect has been kicked off.
class WorkspaceTerminalEntry {
  WorkspaceTerminalEntry({required this.id, required this.cwd})
    : session = TerminalSession(
        executable: WorkspaceInteractiveShell.executable(),
        validateLaunch: false,
        parseExecutable: false,
      ),
      controller = TerminalController();

  final String id;
  String cwd;
  bool connected = false;
  final TerminalSession session;
  final TerminalController controller;

  String title() {
    final shell = p.basename(WorkspaceInteractiveShell.executable());
    if (cwd.isEmpty) return shell;
    return '$shell ${p.basename(cwd)}';
  }

  void dispose() {
    session.disconnect();
    controller.dispose();
  }
}

/// One project's set of workspace-terminal tabs.
class WorkspaceTerminalGroup {
  final List<WorkspaceTerminalEntry> _entries = [];
  String? _activeId;

  List<WorkspaceTerminalEntry> get entries => List.unmodifiable(_entries);
  String? get activeId => _activeId;

  WorkspaceTerminalEntry? get activeEntry {
    final id = _activeId;
    if (id == null) return null;
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  set activeId(String? id) => _activeId = id;

  WorkspaceTerminalEntry addEntry({required String cwd, required bool select}) {
    final entry = WorkspaceTerminalEntry(id: _uuid.v4(), cwd: cwd);
    _entries.add(entry);
    if (select) _activeId = entry.id;
    return entry;
  }

  /// Removes [id], disposing it, and reselects a neighbour. Returns true when
  /// the group is now empty.
  bool removeEntry(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return _entries.isEmpty;
    final wasActive = _entries[index].id == _activeId;
    _entries[index].dispose();
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      _activeId = null;
      return true;
    }
    if (wasActive) {
      final next = index >= _entries.length ? _entries.length - 1 : index;
      _activeId = _entries[next].id;
    }
    return false;
  }

  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    _entries.clear();
    _activeId = null;
  }
}

/// Owns workspace-terminal groups keyed by `projectId`. Lives in DI so terminal
/// sessions survive [WorkspaceTerminalPanel] rebuilds on project switch; a
/// group is torn down only when its project tab is closed ([disposeProject]).
class WorkspaceTerminalRegistry {
  final Map<String, WorkspaceTerminalGroup> _groups = {};

  WorkspaceTerminalGroup groupFor(String projectId) =>
      _groups.putIfAbsent(projectId, WorkspaceTerminalGroup.new);

  void disposeProject(String projectId) {
    _groups.remove(projectId)?.dispose();
  }

  void disposeAll() {
    for (final g in _groups.values) {
      g.dispose();
    }
    _groups.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/terminal/workspace_terminal_registry_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/terminal/workspace_terminal_registry.dart client/test/services/terminal/workspace_terminal_registry_test.dart
git commit -m "feat(terminal): add WorkspaceTerminalRegistry for per-project terminals"
```

### Task 2.2: Provide the registry through DI

**Files:**
- Modify: `client/lib/app/app_shell.dart` (field + constructor + construction)
- Modify: `client/lib/main.dart:165-182` (add `RepositoryProvider.value`)

- [ ] **Step 1: Add field/param/import to `AppShell`**

In `client/lib/app/app_shell.dart` add the import:

```dart
import '../services/terminal/workspace_terminal_registry.dart';
```

Add the constructor param (next to `required this.transportFactory,`):

```dart
    required this.workspaceTerminalRegistry,
```

Add the field (next to `final TerminalTransportFactory transportFactory;`, line 122):

```dart
  final WorkspaceTerminalRegistry workspaceTerminalRegistry;
```

- [ ] **Step 2: Construct it in `buildAppShell`**

Near the other service constructions in `buildAppShell` (before the `AppShell(` return), add:

```dart
  final workspaceTerminalRegistry = WorkspaceTerminalRegistry();
```

Add `workspaceTerminalRegistry: workspaceTerminalRegistry,` to the `AppShell(...)` constructor call.

- [ ] **Step 3: Provide it in `main.dart`**

In the `MultiRepositoryProvider.providers` list (after line 181 `RepositoryProvider<StorageRoots>.value(value: shell.storageRoots),`), add:

```dart
              RepositoryProvider<WorkspaceTerminalRegistry>.value(
                value: shell.workspaceTerminalRegistry,
              ),
```

Add the import at the top of `main.dart` (with other service imports):

```dart
import 'services/terminal/workspace_terminal_registry.dart';
```

- [ ] **Step 4: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(terminal): provide WorkspaceTerminalRegistry via DI"
```

### Task 2.3: Refactor `WorkspaceTerminalPanel` to read the registry

**Files:**
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`

The panel becomes keyed by `projectId`. It no longer owns `_tabs`/`_activeTabId` or disposes sessions on `dispose()`; it reads the project's group from the registry and drives connect/theme.

- [ ] **Step 1: Add `projectId` to the widget and swap internal state for the group**

In `client/lib/widgets/workspace_terminal_panel.dart`:

Add the import:

```dart
import '../services/terminal/workspace_terminal_registry.dart';
```

Replace the widget constructor (lines 30-37) with:

```dart
class WorkspaceTerminalPanel extends StatefulWidget {
  const WorkspaceTerminalPanel({
    required this.projectId,
    required this.workingDirectory,
    super.key,
  });

  final String projectId;
  final String workingDirectory;

  @override
  State<WorkspaceTerminalPanel> createState() => _WorkspaceTerminalPanelState();
}
```

Delete the entire `_WorkspaceTerminalTab` class (lines 39-64) — it is replaced by `WorkspaceTerminalEntry` from the registry.

- [ ] **Step 2: Replace `_WorkspaceTerminalPanelState` storage and lifecycle**

Replace the state fields + lifecycle methods (lines 66-151, from `class _WorkspaceTerminalPanelState` through the end of `_closeTab`) with:

```dart
class _WorkspaceTerminalPanelState extends State<WorkspaceTerminalPanel> {
  WorkspaceTerminalRegistry get _registry =>
      context.read<WorkspaceTerminalRegistry>();
  WorkspaceTerminalGroup get _group => _registry.groupFor(widget.projectId);

  var _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    _ensureDefaultEntry();
  }

  @override
  void didUpdateWidget(WorkspaceTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workingDirectory != widget.workingDirectory ||
        oldWidget.projectId != widget.projectId) {
      _syncActiveEntryCwd();
    }
  }

  // NOTE: no dispose() of sessions here — the registry owns their lifetime and
  // tears them down via disposeProject when the project tab is closed.

  WorkspaceTerminalEntry? get _activeEntry => _group.activeEntry;

  void _ensureDefaultEntry() {
    final cwd = widget.workingDirectory.trim();
    if (_group.entries.isNotEmpty) {
      // Revisiting a project: re-attach controllers to live sessions.
      for (final entry in _group.entries) {
        if (entry.connected && entry.controller.engine == null) {
          entry.controller.attach(entry.session.engine);
        }
      }
      if (mounted) setState(() {});
      return;
    }
    if (cwd.isEmpty) return;
    _addEntry(cwd, select: true);
  }

  void _syncActiveEntryCwd() {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty) return;
    final active = _activeEntry;
    if (active == null) {
      _addEntry(cwd, select: true);
      return;
    }
    if (active.cwd == cwd) return;
    active.cwd = cwd;
    active.connected = false;
    _connectEntry(active);
    setState(() {});
  }

  void _addEntry(String cwd, {required bool select}) {
    final entry = _group.addEntry(cwd: cwd, select: select);
    _connectEntry(entry);
    setState(() {});
  }

  void _closeEntry(String id) {
    final nowEmpty = _group.removeEntry(id);
    if (nowEmpty) {
      if (mounted) {
        context.read<LayoutCubit>().setWorkspaceTerminalVisible(false);
      }
      return;
    }
    setState(() {});
  }
```

- [ ] **Step 3: Update `_connectTab` → `_connectEntry`**

Replace `_connectTab` (lines 164-188) with the same body but the `WorkspaceTerminalEntry` type:

```dart
  void _connectEntry(WorkspaceTerminalEntry entry) {
    final cwd = entry.cwd.trim();
    if (cwd.isEmpty) return;
    if (entry.connected && entry.session.isRunning) return;

    final theme = _terminalTheme(context);
    entry.session.applyTerminalTheme(theme);
    entry.connected = true;
    entry.session.connectShell(
      workingDirectory: cwd,
      onProcessStarted: () {
        if (mounted) setState(() {});
      },
      onProcessFailed: (_) {
        if (mounted) setState(() {});
      },
      onProcessExited: () {
        entry.connected = false;
        if (mounted) setState(() {});
      },
    );
    if (entry.controller.engine == null) {
      entry.controller.attach(entry.session.engine);
    }
  }
```

- [ ] **Step 4: Update remaining references to `tab`/`_tabs`/`_activeTabId`**

In `_showContextMenu`, change the parameter type from `_WorkspaceTerminalTab tab` to `WorkspaceTerminalEntry entry` and rename `tab.` → `entry.` throughout that method (signature line ~190 and body).

In `build()` (lines 277-342): replace `final active = _activeTab;` with `final active = _activeEntry;`; replace the sidebar's `tabs: _tabs,` with `entries: _group.entries,`, `activeTabId: _activeTabId,` with `activeEntryId: _group.activeId,`, `onSelect: (id) => setState(() => _activeTabId = id),` with `onSelect: (id) => setState(() => _group.activeId = id),`, `onCloseTab: _closeTab,` with `onCloseEntry: _closeEntry,`, and `onNewTab:`'s body `_addTab(dir, select: true)` with `_addEntry(dir, select: true)`. Update `_WorkspaceTerminalView(tab: active, ...)` to `_WorkspaceTerminalView(entry: active, ...)` and `_showContextMenu(context, active, position, cell)` accordingly.

- [ ] **Step 5: Update the two private view widgets to the entry type**

In `_WorkspaceTerminalView` (lines 345-380): rename field `tab` → `entry` of type `WorkspaceTerminalEntry`, and all `tab.` → `entry.`.

In `_WorkspaceTerminalSessionSidebar` (lines 382-508): rename `tabs` → `entries` (type `List<WorkspaceTerminalEntry>`), `activeTabId` → `activeEntryId`, `onCloseTab` → `onCloseEntry`, and the `itemBuilder`'s `tab` local → `entry`.

- [ ] **Step 6: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/workspace_terminal_panel.dart`
Expected: No errors. (If `_uuid`/`min` imports are now unused, remove them: the panel no longer needs `uuid`; keep `dart:math` only if `min` is still used — after this refactor `min` is gone, so remove `import 'dart:math' show min;` and `const _uuid = Uuid();` + the `uuid` import.)

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/workspace_terminal_panel.dart
git commit -m "refactor(terminal): drive WorkspaceTerminalPanel from the per-project registry"
```

### Task 2.4: Re-key the terminal panel by `projectId` in the layout

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_layout.dart:10-95`
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart` (thread `projectId`)

- [ ] **Step 1: Add `projectId` through the workspace-shell layout chain**

In `client/lib/pages/workspace_shell/workspace_shell_layout.dart`:

Add `final String? workspaceProjectId;` to `WorkspaceShellMainWithTerminal` (next to `workspaceTerminalWorkingDirectory`) and to its constructor; pass it into `WorkspaceShellCenterColumnWithTerminal`.

Add `final String? workspaceProjectId;` to `WorkspaceShellCenterColumnWithTerminal` and its constructor.

In `WorkspaceShellCenterColumnWithTerminal.build`, replace lines 76-83 (the `ResizableSplitView` `second:` `WorkspaceTerminalPanel`) with:

```dart
        final projectId = workspaceProjectId?.trim() ?? '';
        return ResizableSplitView(
          axis: Axis.vertical,
          primaryAtEnd: true,
          first: child,
          second: WorkspaceTerminalPanel(
            key: ValueKey('workspace-terminal-$projectId-$cwd'),
            projectId: projectId.isNotEmpty ? projectId : cwd,
            workingDirectory: cwd,
          ),
```

(Using `cwd` as the fallback project key keeps non-project chat routes working with a stable per-cwd group.)

- [ ] **Step 2: Thread `projectId` from `WorkspaceShell`**

Read `client/lib/pages/workspace_shell/workspace_shell.dart`. Add an optional `final String? workspaceProjectId;` field + constructor param (next to `this.workspaceTerminalWorkingDirectory,`). Find where it builds `WorkspaceShellMainWithTerminal` (the only construction site) and pass `workspaceProjectId: workspaceProjectId,`.

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/workspace_shell/`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell.dart client/lib/pages/workspace_shell/workspace_shell_layout.dart
git commit -m "feat(terminal): key workspace terminal panel by projectId"
```

---

## Phase 3 — Wire active-project switching end-to-end

### Task 3.1: Thread `projectId` through `ChatPage`

**Files:**
- Modify: `client/lib/pages/chat_page.dart`

- [ ] **Step 1: Add `projectId` to `ChatPage` and its private bodies**

In `client/lib/pages/chat_page.dart`:

Add to `ChatPage` constructor (after `this.isPersonalProject = false,`, line 26):

```dart
    this.projectId,
```

Add the field (after `final bool isPersonalProject;`, line 37):

```dart
  /// Owning project id; scopes the workspace terminal + right-tools selection.
  /// Null on chat routes without a project context.
  final String? projectId;
```

Thread it through: `_PersonalChatPage`, `_TeamChatPage`, and `_ChatPageBody` each get a `final String? projectId;` field + constructor param, and `ChatPage.build` passes `projectId: projectId` into both `_PersonalChatPage(...)` and `_TeamChatPage(...)`; those pass it into `_ChatPageBody(...)`.

- [ ] **Step 2: Pass `projectId` into `WorkspaceShell` and `RightToolsPanel`**

In `_ChatPageBody.build`, add to the `WorkspaceShell(...)` call (after `workspaceTerminalWorkingDirectory: cwd,`, line 131):

```dart
        workspaceProjectId: projectId,
```

And add `projectId: projectId,` to all three `RightToolsPanel(...)` constructions (the `rightToolsPanel` local at line 116, and the inline one at line 174).

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat_page.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat_page.dart
git commit -m "feat(chat): thread projectId through ChatPage to shell + tools"
```

### Task 3.2: Set the active project on switch in `HomeWorkspaceProjectPage`

**Files:**
- Modify: `client/lib/pages/home_workspace/project/home_workspace_project_page.dart`

- [ ] **Step 1: Call `setActiveProject` whenever the project context changes**

In `_onProjectContextChanged()` (lines 74-86), add the `setActiveProject` call at the top (before the team/personal branch):

```dart
  void _onProjectContextChanged() {
    if (!mounted) return;
    context.read<ChatCubit>().setActiveProject(widget.projectId);
    final project = _findProject(
      context.read<ChatCubit>().state.projects,
      widget.projectId,
    );
    if (project == null) return;
    if (project.teamId.isEmpty) {
      _loadPersonalProfile(project.projectId);
      return;
    }
    _syncSelectedTeam(project.teamId);
  }
```

`_onProjectContextChanged` is already invoked from `initState` and from `didUpdateWidget` when `projectId` changes, so this fires on first open and on every project switch.

- [ ] **Step 2: Pass `projectId` into both `ChatPage` constructions**

Change line 137-140 (personal):

```dart
              : ChatPage(
                  cwd: project.primaryPath,
                  projectId: project.projectId,
                  isPersonalProject: true,
                ),
```

Change line 180 (team):

```dart
                  second: ChatPage(
                    cwd: project.primaryPath,
                    projectId: project.projectId,
                  ),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/project/home_workspace_project_page.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/project/home_workspace_project_page.dart
git commit -m "feat(workspace): set active project on project page switch"
```

### Task 3.3: Dispose terminal group + tools state when a project tab closes

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart:136-171`

`_closeTab` already calls `chat.closeTabsForProject(id)` (only when there are running sessions). The terminal group and tools state must be disposed unconditionally on close (a project may have terminals but no chat sessions).

- [ ] **Step 1: Dispose registry group and tools state in `_closeTab`**

In `client/lib/pages/home_workspace/home_workspace_shell.dart`, add the imports:

```dart
import '../../cubits/workspace_tools_cubit.dart';
import '../../services/terminal/workspace_terminal_registry.dart';
```

In `_closeTab` (lines 136-171), after the running-sessions confirm block (after line 147 `chat.closeTabsForProject(id);` / its enclosing `if`), add — placed so it always runs on a confirmed close, before recording the closed entry:

```dart
    // Tear down this project's keep-alive workspace runtime.
    context.read<WorkspaceTerminalRegistry>().disposeProject(id);
    context.read<WorkspaceToolsCubit>().removeProject(id);
    if (running == 0) {
      // No chat sessions to confirm/close, but still drop any chat bucket.
      chat.closeTabsForProject(id);
    }
```

So the method reads: confirm only when `running > 0`; then always dispose terminal + tools; then `closeTabsForProject` for the `running == 0` path (the `running > 0` path already called it inside the confirm block).

- [ ] **Step 2: Verify it compiles**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/home_workspace_shell.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_shell.dart
git commit -m "feat(workspace): dispose terminal + tools state when closing a project tab"
```

---

## Phase 4 — Integration test + full verification

### Task 4.1: Widget test — isolation + keep-alive across project switch

**Files:**
- Create: `client/test/pages/home_workspace/project_isolation_widget_test.dart`

This test verifies the two user-visible guarantees at the cubit/registry seam (no full router boot needed): (1) chat tabs do not leak across projects; (2) a project's terminal group survives a switch and is restored.

- [ ] **Step 1: Write the test**

Create `client/test/pages/home_workspace/project_isolation_widget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('chat tabs do not leak across projects', () {
    final cubit = ChatCubit(executableResolver: () => '/bin/true');
    cubit.setActiveProject('personal-A');
    cubit.tabStore.append(_tab('a-sess'));
    cubit.refreshActiveProjectTabs();
    expect(cubit.state.tabs.map((t) => t.id), ['a-sess']);

    // Two personal projects (both empty teamId) must not see each other's tabs.
    cubit.setActiveProject('personal-B');
    expect(cubit.state.tabs, isEmpty);

    cubit.setActiveProject('personal-A');
    expect(cubit.state.tabs.map((t) => t.id), ['a-sess']);
    addTearDown(cubit.close);
  });

  test('terminal group survives a project switch and is restored', () {
    final reg = WorkspaceTerminalRegistry();
    final groupA = reg.groupFor('A');
    final entry = groupA.addEntry(cwd: '/tmp/a', select: true);

    // Switch to B (group A is untouched in the registry).
    reg.groupFor('B');

    // Switch back to A: same group, same entry, same session instance.
    final restored = reg.groupFor('A');
    expect(identical(restored, groupA), isTrue);
    expect(restored.entries.single.id, entry.id);
    expect(identical(restored.entries.single.session, entry.session), isTrue);

    // Closing A's project tab disposes it.
    reg.disposeProject('A');
    expect(reg.groupFor('A').entries, isEmpty);
    reg.disposeAll();
  });
}
```

- [ ] **Step 2: Run it to verify it passes**

Run: `cd client && flutter test test/pages/home_workspace/project_isolation_widget_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 3: Commit**

```bash
git add client/test/pages/home_workspace/project_isolation_widget_test.dart
git commit -m "test(workspace): cover project isolation + terminal keep-alive"
```

### Task 4.2: Full analyze + test sweep

- [ ] **Step 1: Run the full gate**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```
Expected: analyze clean; all tests pass. Fix any fallout (most likely: a pre-existing test that builds tabs without `setActiveProject` — those default to the `''` bucket and should still pass; if a test asserts cross-project visibility that no longer holds, update it to the new isolation semantics).

- [ ] **Step 2: Manual golden-path check (document result in the PR)**

Because CI cannot drive the PTY/router, manually verify on Linux desktop:
1. Open project A, open a chat session + run a command in the workspace terminal.
2. Open project B (new tab). Confirm B shows no A tabs and an empty/own terminal.
3. Switch back to A. Confirm A's chat tabs are intact and the terminal still shows the earlier command output (scrollback preserved).
4. Switch the right-tools tab in A (e.g. to Git), switch to B, back to A — A still shows Git selected; B shows its own default.
5. Close project A's tab (confirm dialog if sessions running). Reopen A — fresh terminal/tabs (group was disposed).

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(workspace): address analyze/test fallout for project isolation"
```

---

## Self-Review notes (for the implementer)

- **Spec coverage:** ChatCubit bucketing (spec §②) → Phase 1; WorkspaceTerminalRegistry (§③) → Phase 2; WorkspaceToolsStore (§④) → Phase 0; active-project wiring (§④/⑤) → Phase 3; lifecycle/disposal (§⑤) → Task 3.3; tests (§⑦) → each phase + Phase 4; layering (§⑧) → new files placed under `services/` and `cubits/`.
- **Out of scope (per spec):** layout sizes/visibility stay global (`LayoutCubit` untouched); no cross-restart scrollback persistence; no keep-alive cap/LRU.
- **Type consistency:** `WorkspaceTerminalEntry`/`WorkspaceTerminalGroup`/`WorkspaceTerminalRegistry` names are used identically across Tasks 2.1–2.4 and 4.1. `setActiveProject(String, {int? currentActiveIndex})` signature matches between store (Task 1.2) and cubit (Task 1.3). `refreshActiveProjectTabs()`/`openTabCountForProject()`/`closeTabsForProject()` names match across tests and impl.
- **Risk note:** the largest single edit is Task 2.3 (`WorkspaceTerminalPanel`). Do it as a mechanical rename (`tab`→`entry`, local `_tabs`→`_group`) and lean on `flutter analyze` between steps.
