import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/agent_permission_attention_banner.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final workbenchViews = <(String, SessionWorkbenchView)>[];
  final selectedMembers = <String>[];

  @override
  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    workbenchViews.add((sessionId, view));
    super.setSessionWorkbenchView(sessionId, view);
  }

  @override
  void selectMember(String memberId) {
    selectedMembers.add(memberId);
    super.selectMember(memberId);
  }
}

AppSession _simpleSession({String id = 'sess-1'}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp')],
    createdAt: 1,
    updatedAt: 1,
  );
}

Widget _harness({
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
          body: AgentPermissionAttentionBanner(session: session),
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('banner visible when waiting + History; tap opens Terminal', (
    tester,
  ) async {
    final session = _simpleSession();
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.tabStore.setActiveWorkspace(session.workspaceId);
    chat.tabStore.append(
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
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsOneWidget);
    expect(
      find.text('This agent needs confirmation in the Terminal.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppKeys.agentPermissionOpenTerminalButton));
    await tester.pumpAndSettle();

    expect(chat.workbenchViews, [
      (session.sessionId, SessionWorkbenchView.terminal),
    ]);
    expect(
      chat.tabStore.openTabBySessionId(session.sessionId)?.workbenchView,
      SessionWorkbenchView.terminal,
    );
    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
  });

  testWidgets('banner hidden when seat is not waiting', (tester) async {
    final session = _simpleSession();
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.tabStore.setActiveWorkspace(session.workspaceId);
    chat.tabStore.append(
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

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
  });

  testWidgets('banner hidden when workbench is Terminal', (tester) async {
    final session = _simpleSession();
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.tabStore.setActiveWorkspace(session.workspaceId);
    chat.tabStore.append(
      ChatTab(
        info: ChatTabInfo(
          id: session.sessionId,
          title: 'Chat',
          subtitle: 'simple',
        ),
        cliTeamName: '',
        workbenchView: SessionWorkbenchView.terminal,
      ),
    );

    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(attention.close);
    attention.applyEvent(
      sessionId: session.sessionId,
      memberId: session.sessionId,
      event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
  });
}
