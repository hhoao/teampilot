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
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
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
  void selectMember(String memberId, {String? tabScopeId}) {
    selectedMembers.add(memberId);
    super.selectMember(memberId);
  }
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

Widget _harness({
  required ChatCubit chat,
  required AgentAttentionCubit attention,
  required AppSession session,
  String selectedMemberId = '',
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
            selectedMemberId: selectedMemberId,
          ),
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

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
  });

  testWidgets('ExitPlanMode shows plan card and opens Terminal', (
    tester,
  ) async {
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
        toolName: 'ExitPlanMode',
        planText: '1. Refactor the launcher.\n2. Add tests.',
        planFilePath: '/tmp/plan.md',
      ),
      skipPermissions: true,
    );

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeCard), findsOneWidget);
    expect(
      find.textContaining('Refactor the launcher'),
      findsNothing,
      reason: 'plan content renders only in the floating preview',
    );
    expect(find.byKey(AppKeys.exitPlanModeViewPlanButton), findsOneWidget);
    expect(find.text('/tmp/plan.md'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.agentPermissionOpenTerminalButton));
    await tester.pumpAndSettle();

    expect(chat.workbenchViews, [
      (session.sessionId, SessionWorkbenchView.terminal),
    ]);
  });

  testWidgets('PermissionRequest plan echo card keeps approve buttons', (
    tester,
  ) async {
    final session = _simpleSession(id: 'sess-plan-echo');
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
        hookEventName: 'PermissionRequest',
        toolName: 'ExitPlanMode',
        planText: '1. Revised plan.',
        planFilePath: '/tmp/plan-2.md',
      ),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.exitPlanModeCard), findsOneWidget);
    // The seat-keyed permission gate makes this actionable from chat even
    // though the event carries no tool_use_id.
    expect(find.byKey(AppKeys.exitPlanModeApproveButton), findsOneWidget);
    expect(find.byKey(AppKeys.exitPlanModeRejectButton), findsOneWidget);
  });

  testWidgets('opencode permission.asked shows permission card', (
    tester,
  ) async {
    final session = _simpleSession(id: 'sess-perm', cli: CliTool.opencode);
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
        hookEventName: 'permission.asked',
        askRequestId: 'perm-1',
        permissionRequest: AgentPermissionRequest(
          id: 'perm-1',
          description: 'Run `npm install`',
          always: [AgentPermissionAlwaysOption(label: 'npm install')],
        ),
      ),
      skipPermissions: false,
    );

    await tester.pumpWidget(
      _harness(chat: chat, attention: attention, session: session),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.opencodePermissionCard), findsOneWidget);
    expect(find.textContaining('npm install'), findsWidgets);
    // Terminal banner must not double-render for the interactive card.
    expect(find.byKey(AppKeys.agentPermissionAttentionBanner), findsNothing);
  });

  testWidgets('banner hidden when workbench is Terminal', (tester) async {
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
