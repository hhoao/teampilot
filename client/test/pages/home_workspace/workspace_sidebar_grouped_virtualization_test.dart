import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session({
  required String id,
  String display = '',
  int createdAt = 1,
  int updatedAt = 1,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: _workspace.workspaceId,
    folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionRepository sessionRepository;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository();
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit();
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
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
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>(
                  lazy: false,
                  create: (_) => chatCubit,
                ),
                BlocProvider<WorkbenchCubit>(create: (_) => WorkbenchCubit()),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
              ],
              child: SizedBox(
                width: 320,
                height: 1000,
                child: WorkspaceSidebar(
                  workspace: _workspace,
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

  Future<void> expandGroup(WidgetTester tester) async {
    await tester.tap(find.text('More'));
    await tester.pump();
  }

  testWidgets(
    'collapsed group caps at 8 natural rows; expanded becomes a fixed '
    '10-row scrollable that stays virtualized',
    (tester) async {
      final n = 300;
      await emitSessions([
        for (var i = 0; i < n; i++)
          _session(id: 's$i', display: 'Session $i', createdAt: n - i),
      ]);
      await pumpSidebar(tester);

      // Non-git folder → single project group, collapsed by default: 8 rows
      // at natural height + a "More" toggle. No scrollable extra height.
      final listFinder = find.byType(ReorderableListView);
      expect(listFinder, findsOneWidget);
      expect(mountedTiles(tester), 8);
      expect(find.text('More'), findsOneWidget);
      expect(tester.getSize(listFinder).height, 8 * 46);

      await expandGroup(tester);
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.getSize(listFinder).height, 10 * 46);
      final mounted = mountedTiles(tester);
      expect(mounted, greaterThan(8));
      expect(mounted, lessThan(60));
      expect(mounted, lessThan(n));

      // Scrolling the expanded area reveals the bottom sessions without
      // mounting everything.
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: listFinder,
          matching: find.byType(Scrollable),
        ),
      );
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(find.text('Session 299'), findsOneWidget);
      expect(find.text('Session 0'), findsNothing);
      expect(mountedTiles(tester), lessThan(60));

      // Toggle back to the collapsed cap.
      await tester.tap(find.text('Show less'));
      await tester.pump();
      expect(mountedTiles(tester), 8);
      expect(tester.getSize(listFinder).height, 8 * 46);
    },
  );

  testWidgets('groups at or under the cap have no toggle and natural height', (
    tester,
  ) async {
    await emitSessions([
      _session(id: 'a', display: 'Alpha', createdAt: 3),
      _session(id: 'b', display: 'Beta', createdAt: 2),
      _session(id: 'c', display: 'Gamma', createdAt: 1),
    ]);
    await pumpSidebar(tester);

    expect(find.text('More'), findsNothing);
    expect(tester.getSize(find.byType(ReorderableListView)).height, 138);
    expect(mountedTiles(tester), 3);

    // Exactly the cap: still no toggle, full natural height.
    await emitSessions([
      for (var i = 0; i < 8; i++)
        _session(id: 's$i', display: 'Session $i', createdAt: 8 - i),
    ]);
    await tester.pump();
    expect(find.text('More'), findsNothing);
    expect(mountedTiles(tester), 8);
    expect(tester.getSize(find.byType(ReorderableListView)).height, 8 * 46);
  });

  testWidgets('collapsing a group hides its sessions; re-expanding shows them', (
    tester,
  ) async {
    await emitSessions([
      for (var i = 0; i < 20; i++)
        _session(id: 's$i', display: 'Session $i', createdAt: 20 - i),
    ]);
    await pumpSidebar(tester);

    expect(mountedTiles(tester), 8);
    final headerKey = find.byKey(
      const ValueKey('worktree-group-header-probe-project:/tmp/ws-1'),
    );
    await tester.tap(headerKey);
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsNothing);

    // Re-expanding resets the list to the collapsed 8-row cap.
    await tester.tap(headerKey);
    await tester.pump();
    expect(mountedTiles(tester), 8);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets(
    'grouped drag stamps the workspace sort order via group merge',
    (tester) async {
      final worktrees = [
        GitWorktree(
          path: '/tmp/ws-1',
          branch: 'refs/heads/main',
          head: 'abc1111',
          isBare: false,
          isMainWorktree: true,
        ),
        GitWorktree(
          path: '/tmp/ws-1/wt-feature',
          branch: 'refs/heads/feature',
          head: 'abc2222',
          isBare: false,
          isMainWorktree: false,
        ),
      ];
      worktreeCubit.emit(
        worktreeCubit.state.copyWith(
          worktrees: worktrees,
          currentWorktreePath: worktrees.first.path,
          loading: false,
        ),
      );
      await emitSessions([
        _session(id: 'a', display: 'A', createdAt: 6),
        _session(id: 'b', display: 'B', createdAt: 5),
        _session(id: 'c', display: 'C', createdAt: 4),
        _session(id: 'd', display: 'D', createdAt: 3),
        _session(id: 'e', display: 'E', createdAt: 2),
        _session(id: 'f', display: 'F', createdAt: 1),
      ]);
      await pumpSidebar(tester);

      // Two group lists exist; the first one belongs to the main worktree.
      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView).first,
      );
      // Rows inside the main group: [a, b, c]. Move c (index 2) above a.
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
    },
  );
}
