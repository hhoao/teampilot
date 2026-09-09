import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  display: id,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionGroupsCubit groupsCubit;
  late SessionRepository sessionRepository;
  late WorkbenchCubit workbenchCubit;

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
    groupsCubit = SessionGroupsCubit();
    workbenchCubit = WorkbenchCubit();
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    if (!workbenchCubit.isClosed) await workbenchCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    await tester.runAsync(() => groupsCubit.load(_workspace.workspaceId));
    chatCubit.emit(
      chatCubit.state.copyWith(sessions: [_session('a'), _session('b')]),
    );
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
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider<WorkbenchCubit>.value(value: workbenchCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
                BlocProvider(create: (_) => ShortcutCubit()),
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
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('split layout renders open sessions grouped by column', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab('ws-1', WorkbenchTabId.session('b'), axis: Axis.horizontal, before: false);
    await pumpSidebar(tester);

    // Two split sub-sections, each with its divider and tiles.
    expect(
      find.byKey(const ValueKey('workspace-running-split-g0')),
      findsOneWidget,
    );
    final second = workbenchCubit.centerLayout('ws-1').leafGroupIds.last;
    expect(
      find.byKey(ValueKey('workspace-running-split-$second')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
  });

  testWidgets('single group stays flat without column dividers', (
    tester,
  ) async {
    workbenchCubit.openSession('ws-1', 'a');
    await pumpSidebar(tester);

    expect(
      find.byKey(const ValueKey('workspace-running-split-g0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
  });

  testWidgets('preview sessions render in the open strip with italic title', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b', preview: true)
      ..openSession('ws-1', 'c');
    await pumpSidebar(tester);

    // The preview tab 'b' surfaces in the flat open strip next to pinned tabs.
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
    // And its title is italic (distinct preview treatment).
    final tile = tester.widget<SidebarSessionTile>(
      find.byKey(const ValueKey('workspace-running-session-b')),
    );
    expect(tile.preview, isTrue);
    final pinned = tester.widget<SidebarSessionTile>(
      find.byKey(const ValueKey('workspace-running-session-a')),
    );
    expect(pinned.preview, isFalse);
  });

  testWidgets('tapping a group indicator focuses that group', (tester) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab('ws-1', WorkbenchTabId.session('b'), axis: Axis.horizontal, before: false);
    await pumpSidebar(tester);

    final layoutBefore = workbenchCubit.centerLayout('ws-1');
    final focusedBefore = layoutBefore.focusedGroupId;

    // One indicator per tile, keyed by its split group.
    final g0Indicator = find.byKey(
      const ValueKey('workspace-running-group-indicator-g0'),
    );
    expect(g0Indicator, findsOneWidget);
    await tester.tap(g0Indicator);
    await tester.pump();

    final layoutAfter = workbenchCubit.centerLayout('ws-1');
    expect(layoutAfter.focusedGroupId, isNot(focusedBefore));
  });
}
