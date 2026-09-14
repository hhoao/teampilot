import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/pages/home_workspace/workspace/worktree_group_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/utils/session/session_worktree_grouping.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../support/post_frame_test_harness.dart';
import 'package:teampilot/services/storage/home_storage.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/huji')],
  createdAt: 1,
);

AppSession _session({
  required String id,
  String display = '',
  int createdAt = 1,
  int updatedAt = 1,
  String path = '/tmp/huji',
}) {
  return AppSession(
    sessionId: id,
    workspaceId: _workspace.workspaceId,
    folders: [WorkspaceFolder(path: path)],
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionRepository sessionRepository;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository(storage: testHomeStorage);
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit(storage: testHomeStorage);
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(
    WidgetTester tester, {
    double height = 1000,
    Workspace? workspace,
  }) async {
    final effectiveWorkspace = workspace ?? _workspace;
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>(lazy: false, create: (_) => chatCubit),
                BlocProvider(
                  create: (_) => MemberPresenceCubit(storage: testHomeStorage),
                ),
                BlocProvider<WorkbenchCubit>(create: (_) => WorkbenchCubit()),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>(
                  create: (_) => SessionGroupsCubit(storage: testHomeStorage),
                ),
                BlocProvider(
                  create: (_) => ShortcutCubit(storage: testHomeStorage),
                ),
              ],
              child: SizedBox(
                width: 320,
                height: height,
                child: WorkspaceSidebar(
                  workspace: effectiveWorkspace,
                  tabScopeId: 'ws-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> emitSessions(List<AppSession> sessions) async {
    chatCubit.emit(chatCubit.state.copyWith(sessions: sessions));
    await null;
  }

  int mountedTiles(WidgetTester tester) =>
      tester.widgetList(find.byType(SidebarSessionTile)).length;

  testWidgets('groups mode uses one flat reorderable list', (tester) async {
    await emitSessions([
      _session(id: 'a', display: 'Alpha', createdAt: 3),
      _session(id: 'b', display: 'Beta', createdAt: 2),
      _session(id: 'c', display: 'Gamma', createdAt: 1),
    ]);
    await pumpSidebar(tester);

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('More'), findsNothing);
    expect(mountedTiles(tester), 3);
    expect(
      find.byKey(const ValueKey('project-tree-node-/tmp/huji')),
      findsNothing,
    );
  });

  testWidgets('groups mode keeps a large flat list virtualized', (
    tester,
  ) async {
    const n = 300;
    await emitSessions([
      for (var i = 0; i < n; i++)
        _session(id: 's$i', display: 'Session $i', createdAt: n - i),
    ]);
    await pumpSidebar(tester);

    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(mountedTiles(tester), lessThan(n));
    expect(find.text('Session 299'), findsNothing);
  });

  testWidgets('project tree mode has project nodes with session children', (
    tester,
  ) async {
    await emitSessions([
      _session(id: 'a', display: 'Alpha', createdAt: 2),
      _session(id: 'b', display: 'Beta', createdAt: 1),
    ]);
    await pumpSidebar(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
        matching: find.text('Project tree'),
      ),
    );
    await tester.pump();
    expect(find.byType(ReorderableListView), findsNothing);
    expect(
      find.byKey(const ValueKey('project-tree-node-/tmp/huji')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-tree-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-tree-session-b')),
      findsOneWidget,
    );
  });

  testWidgets('project tree expanded sessions scroll inside the sidebar', (
    tester,
  ) async {
    final workspace = Workspace(
      workspaceId: _workspace.workspaceId,
      folders: [
        const WorkspaceFolder(path: '/tmp/huji'),
        for (var i = 0; i < 10; i++) WorkspaceFolder(path: '/tmp/project-$i'),
      ],
      createdAt: 1,
    );
    await emitSessions([
      for (var i = 0; i < 12; i++)
        _session(id: 's$i', display: 'Session $i', createdAt: 12 - i),
      for (var i = 0; i < 10; i++)
        _session(id: 'other-$i', display: 'Other $i', path: '/tmp/project-$i'),
    ]);
    await pumpSidebar(tester, workspace: workspace);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
        matching: find.text('Project tree'),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pump();
    final sessionList = find.byKey(
      const ValueKey('project-tree-session-list-/tmp/huji'),
    );
    expect(sessionList, findsOneWidget);
    final innerList = find.descendant(
      of: sessionList,
      matching: find.byType(Scrollable),
    );
    final innerState = tester.state<ScrollableState>(innerList);
    expect(innerState.position.maxScrollExtent, greaterThan(0));
    final outerState = tester.state<ScrollableState>(
      find.byType(Scrollable).at(1),
    );
    expect(outerState.position.maxScrollExtent, greaterThan(0));

    final before = innerState.position.pixels;
    await tester.dragFrom(tester.getCenter(innerList), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(innerState.position.pixels, greaterThan(before));

    final afterDrag = innerState.position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(innerList),
        scrollDelta: const Offset(0, -100),
      ),
    );
    await tester.pump();
    expect(innerState.position.pixels, lessThan(afterDrag));
  });

  testWidgets('expanded worktree group consumes drag and wheel scrolling', (
    tester,
  ) async {
    final sessions = [
      for (var i = 0; i < 12; i++)
        _session(id: 'worktree-$i', display: 'Worktree $i'),
    ];
    chatCubit.emit(chatCubit.state.copyWith(sessions: sessions));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
              ],
              child: SizedBox(
                width: 320,
                height: 700,
                child: ListView(
                  children: [
                    WorktreeGroupSection(
                      group: WorktreeGroup(
                        worktree: const GitWorktree(
                          path: '/tmp/huji',
                          branch: 'refs/heads/main',
                          head: 'abc1234',
                          isBare: false,
                          isMainWorktree: true,
                        ),
                        sessions: sessions,
                      ),
                      workspace: _workspace,
                      tabScopeId: 'ws-1',
                      collapsed: false,
                      sessionSort: AppSessionSort.recentlyUpdated,
                      workspaceOrderedSessionIds: [
                        for (final session in sessions) session.sessionId,
                      ],
                      onSessionsReordered: (_) {},
                    ),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pump();

    final innerList = find.byType(ReorderableListView);
    final innerScrollable = find.descendant(
      of: innerList,
      matching: find.byType(Scrollable),
    );
    final innerState = tester.state<ScrollableState>(innerScrollable);
    final outerState = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(innerState.position.maxScrollExtent, greaterThan(0));
    expect(outerState.position.maxScrollExtent, greaterThan(0));

    final outerBeforeDrag = outerState.position.pixels;
    final innerBeforeDrag = innerState.position.pixels;
    await tester.dragFrom(
      tester.getCenter(innerScrollable),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();
    expect(innerState.position.pixels, greaterThan(innerBeforeDrag));
    expect(outerState.position.pixels, outerBeforeDrag);

    final outerBeforeWheel = outerState.position.pixels;
    final innerBeforeWheel = innerState.position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(innerScrollable),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    expect(innerState.position.pixels, isNot(innerBeforeWheel));
    expect(outerState.position.pixels, outerBeforeWheel);

    await tester.dragFrom(
      tester.getCenter(innerScrollable),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(innerState.position.pixels, innerState.position.maxScrollExtent);
    expect(outerState.position.pixels, greaterThan(outerBeforeWheel));
  });

  testWidgets('flat drag stamps the workspace sort order', (tester) async {
    await emitSessions([
      _session(id: 'a', display: 'A', createdAt: 6),
      _session(id: 'b', display: 'B', createdAt: 5),
      _session(id: 'c', display: 'C', createdAt: 4),
      _session(id: 'd', display: 'D', createdAt: 3),
      _session(id: 'e', display: 'E', createdAt: 2),
      _session(id: 'f', display: 'F', createdAt: 1),
    ]);
    await pumpSidebar(tester);

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(2, 0);
    await tester.pump();

    final order = {
      for (final s in chatCubit.state.sessions) s.sessionId: s.sortOrder,
    };
    expect(order['c'], 1);
    expect(order['a'], 2);
    expect(order['b'], 3);
    expect(order['d'], 4);
    expect(order['e'], 5);
    expect(order['f'], 6);
  });
}
