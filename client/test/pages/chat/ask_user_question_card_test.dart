import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/agent_permission_attention_banner.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );
}

AppSession _simpleSession({
  String id = 'sess-1',
  CliTool cli = CliTool.claude,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
    cli: cli,
  );
}

Widget _bannerHarness({
  required ChatCubit chat,
  required AgentAttentionCubit attention,
  required AppSession session,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chat),
          BlocProvider<AgentAttentionCubit>.value(value: attention),
        ],
        child: Scaffold(
          body: AgentPermissionAttentionBanner(
            session: session,
            selectedMemberId: '',
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const singleQuestion = AgentAskUserQuestion(
    question: 'Pick color?',
    header: 'Color',
    options: [
      AgentAskUserOption(label: 'Red'),
      AgentAskUserOption(label: 'Blue'),
    ],
  );

  group('AgentPermissionAttentionBanner ask card', () {
    testWidgets('shows ask card instead of terminal banner', (tester) async {
      final session = _simpleSession();
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      chat.tabStore.setActiveWorkspaceId(session.workspaceId);
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'Chat',
            subtitle: 'simple',
          ),
          cliTeamName: '',
          workbenchView: SessionWorkbenchView.chat,
        ),
      );

      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: session.sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'AskUserQuestion',
          toolUseId: 'toolu-1',
          askRequestId: 'toolu-1',
          askUserQuestions: [singleQuestion],
        ),
        skipPermissions: false,
      );

      await tester.pumpWidget(
        _bannerHarness(chat: chat, attention: attention, session: session),
      );
      await pumpUntilSettled(tester);

      expect(find.byKey(AppKeys.askUserQuestionCard), findsOneWidget);
      expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
      expect(
        AgentPermissionAttentionBanner.isSelectedSeatAskCard(
          attention: attention,
          session: session,
          selectedMemberId: '',
          seatCli: CliTool.claude,
        ),
        isTrue,
      );
    });

    testWidgets('Cursor seat keeps terminal confirmation banner', (
      tester,
    ) async {
      final session = _simpleSession(cli: CliTool.cursor);
      final chat = _RecordingChatCubit();
      addTearDown(chat.close);
      chat.tabStore.setActiveWorkspaceId(session.workspaceId);
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'Chat',
            subtitle: 'simple',
          ),
          cliTeamName: '',
          workbenchView: SessionWorkbenchView.chat,
        ),
      );

      final attention = AgentAttentionCubit(pruneInterval: null);
      addTearDown(attention.close);
      attention.applyEvent(
        sessionId: session.sessionId,
        memberId: session.sessionId,
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PreToolUse',
          toolName: 'AskUserQuestion',
          toolUseId: 'toolu-1',
          askRequestId: 'toolu-1',
          askUserQuestions: [singleQuestion],
        ),
        skipPermissions: false,
      );

      await tester.pumpWidget(
        _bannerHarness(chat: chat, attention: attention, session: session),
      );
      await pumpUntilSettled(tester);

      expect(find.byKey(AppKeys.askUserQuestionCard), findsNothing);
      expect(
        find.byKey(AppKeys.agentPermissionAttentionBanner),
        findsOneWidget,
      );
      expect(
        AgentPermissionAttentionBanner.isSelectedSeatAskCard(
          attention: attention,
          session: session,
          selectedMemberId: '',
          seatCli: CliTool.cursor,
        ),
        isFalse,
      );
    });
  });
}
