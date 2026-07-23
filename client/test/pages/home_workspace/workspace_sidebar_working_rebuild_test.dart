import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar_probe.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/session_working_spinner.dart';

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

SidebarRebuildProbeState _probeState(WidgetTester tester, Key key) {
  return tester.state<SidebarRebuildProbeState>(find.byKey(key));
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

  testWidgets(
    'running strip visible when working before mount',
    (tester) async {
      chatCubit.emit(
        chatCubit.state.copyWith(
          sessions: [
            _session(id: 'a', display: 'Alpha'),
          ],
          workingSessionIds: {'a'},
        ),
      );
      await pumpSidebar(tester);
      expect(find.text('Running'), findsOneWidget);
    },
  );

  testWidgets(
    'working-only emit rebuilds running host but not conversation list shell',
    (tester) async {
      chatCubit.emit(
        chatCubit.state.copyWith(
          sessions: [
            _session(id: 'a', display: 'Alpha'),
            _session(id: 'b', display: 'Beta'),
          ],
        ),
      );

      await pumpSidebar(tester);

      expect(
        find.byKey(const Key('workspace-sidebar-running-host-probe')),
        findsOneWidget,
      );

      final conversationProbe = _probeState(
        tester,
        WorkspaceSidebarKeys.conversationListProbe,
      );
      final runningProbe = _probeState(
        tester,
        WorkspaceSidebarKeys.runningHostProbe,
      );
      final groupHeaderProbe = _probeState(
        tester,
        const ValueKey('worktree-group-header-probe-project:/tmp/ws-1'),
      );
      final conversationBuilds = conversationProbe.buildCount;
      final runningBuilds = runningProbe.buildCount;
      final groupHeaderBuilds = groupHeaderProbe.buildCount;

      chatCubit.updateWorkingSessionsForTest({'a'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Running'), findsOneWidget);
      expect(
        conversationProbe.buildCount,
        conversationBuilds,
        reason: 'conversation list host must not rebuild on working-only',
      );
      expect(
        groupHeaderProbe.buildCount,
        groupHeaderBuilds,
        reason: 'worktree group header must not rebuild on working-only',
      );
      expect(
        runningProbe.buildCount,
        greaterThan(runningBuilds),
        reason: 'running host must rebuild when membership changes',
      );

      final alphaTile = find.byKey(
        const ValueKey('worktree-session-a'),
      );
      expect(alphaTile, findsOneWidget);
      expect(
        find.descendant(
          of: alphaTile,
          matching: find.byType(SessionWorkingSpinner),
        ),
        findsOneWidget,
      );

      final betaTile = find.byKey(
        const ValueKey('worktree-session-b'),
      );
      expect(
        find.descendant(
          of: betaTile,
          matching: find.byType(SessionWorkingSpinner),
        ),
        findsNothing,
      );
    },
  );
}
