import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/session_workbench_view_toggle.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final connects = <SessionConnectRequest>[];

  @override
  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    connects.add(request);
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpToggle(
    WidgetTester tester, {
    required ChatCubit chat,
    required WorkbenchCubit workbench,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chat),
          BlocProvider<WorkbenchCubit>.value(value: workbench),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SessionWorkbenchViewToggle(
              workspaceId: 'w1',
              tabScopeId: 'w1',
            ),
          ),
        ),
      ),
    );
  }

  void surfaceSession(
    ChatCubit chat,
    WorkbenchCubit workbench, {
    required String sessionId,
    String sessionTeam = '',
    String selectedMemberId = '',
  }) {
    chat.tabStore.setActiveWorkspaceId('w1');
    final session = AppSession(
      sessionId: sessionId,
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/w')],
      sessionTeam: sessionTeam,
      createdAt: 1,
      updatedAt: 1,
    );
    chat.tabStore.registerSession(
      ChatTab(
        info: ChatTabInfo(id: sessionId, title: 'S', subtitle: ''),
        cliTeamName: '',
      )
        ..persistedSession = session
        ..selectedMemberId = selectedMemberId,
    );
    workbench.openSession('w1', sessionId);
  }

  IconData toggleIcon(WidgetTester tester) {
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(AppKeys.sessionWorkbenchViewToggle),
        matching: find.byType(Icon),
      ),
    );
    return icon.icon!;
  }

  testWidgets(
    'idle simple session: tapping show-terminal switches to Terminal and connects',
    (tester) async {
      final chat = _RecordingChatCubit();
      final workbench = WorkbenchCubit();
      addTearDown(chat.close);
      addTearDown(workbench.close);
      surfaceSession(chat, workbench, sessionId: 's1');

      await pumpToggle(tester, chat: chat, workbench: workbench);

      // On Chat → toggle offers Terminal.
      expect(toggleIcon(tester), Icons.terminal_rounded);

      await tester.tap(find.byKey(AppKeys.sessionWorkbenchViewToggle));
      await tester.pump();

      expect(chat.connects, hasLength(1));
      final request = chat.connects.single as ExistingSessionConnect;
      expect(request.session.sessionId, 's1');
      expect(request.preserveWorkbenchView, isFalse);
      // The toggle switched the tab's view to Terminal before connecting.
      expect(chat.tabStore.openTabBySessionId('s1')!.workbenchView,
          SessionWorkbenchView.terminal);
    },
  );

  testWidgets(
    'idle team session: show-terminal lazy-spawns only (no full connect)',
    (tester) async {
      final chat = _RecordingChatCubit();
      final workbench = WorkbenchCubit();
      addTearDown(chat.close);
      addTearDown(workbench.close);
      surfaceSession(
        chat,
        workbench,
        sessionId: 's-team',
        sessionTeam: 'team-1',
        selectedMemberId: 'developer',
      );

      await pumpToggle(tester, chat: chat, workbench: workbench);

      await tester.tap(find.byKey(AppKeys.sessionWorkbenchViewToggle));
      await tester.pump();

      expect(chat.connects, isEmpty);
      expect(
        chat.tabStore.openTabBySessionId('s-team')!.workbenchView,
        SessionWorkbenchView.terminal,
      );
    },
  );

  testWidgets(
    'connect that forced Terminal keeps the toggle (tab read) in sync',
    (tester) async {
      final chat = _RecordingChatCubit();
      final workbench = WorkbenchCubit();
      addTearDown(chat.close);
      addTearDown(workbench.close);
      surfaceSession(chat, workbench, sessionId: 's1');

      // Connect-time force: the launch surface writes the pod view through the
      // host port. The tab must follow so the toggle reports Terminal, not a
      // stale Chat.
      chat.setPodView('s1', SessionWorkbenchView.terminal);

      await pumpToggle(tester, chat: chat, workbench: workbench);

      // Center (pod) shows Terminal → toggle offers Chat.
      expect(toggleIcon(tester), Icons.chat_bubble_outline_rounded);
      expect(chat.tabStore.openTabBySessionId('s1')!.workbenchView,
          SessionWorkbenchView.terminal);
    },
  );

  testWidgets('toggle reads the pod view even when the tab copy is stale',
      (tester) async {
    final chat = _RecordingChatCubit();
    final workbench = WorkbenchCubit();
    addTearDown(chat.close);
    addTearDown(workbench.close);
    surfaceSession(chat, workbench, sessionId: 's1');

    // Directly set the pod (canonical) to Terminal and leave the transition
    // copy stale — the toggle must mirror the pod, like the workbench body.
    chat.ensurePodRuntime('s1').setView(SessionWorkbenchView.terminal);
    chat.tabStore.openTabBySessionId('s1')!.workbenchView =
        SessionWorkbenchView.chat;

    await pumpToggle(tester, chat: chat, workbench: workbench);

    expect(toggleIcon(tester), Icons.chat_bubble_outline_rounded);
  });
}
