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

    expect(find.text('Column 1'), findsOneWidget);
    expect(find.text('Column 2'), findsOneWidget);
    // Open-strip tiles render under their column headers.
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
  });

  testWidgets('single group stays flat without column headers', (
    tester,
  ) async {
    workbenchCubit.openSession('ws-1', 'a');
    await pumpSidebar(tester);

    expect(find.text('Column 1'), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a column header focuses that group', (tester) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab('ws-1', WorkbenchTabId.session('b'), axis: Axis.horizontal, before: false);
    await pumpSidebar(tester);

    final layoutBefore = workbenchCubit.centerLayout('ws-1');
    final focusedBefore = layoutBefore.focusedGroupId;

    await tester.tap(find.text('Column 1'));
    await tester.pump();

    final layoutAfter = workbenchCubit.centerLayout('ws-1');
    expect(layoutAfter.focusedGroupId, isNot(focusedBefore));
  });
}
