import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => false;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

  @override
  Stream<AgentPermissionRequest> get permissionRequests => const Stream.empty();

  @override
  Stream<AcpPendingClientRequest> get clientRequests => const Stream.empty();

  @override
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async => reply;

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {}

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() {}

  @override
  Future<void> close() async {}
}

AcpChatRuntimeCubit _cubit(String sessionId, {String seatMemberId = 'acp'}) {
  return AcpChatRuntimeCubit(
    runtime: _FakeAcpRuntime(),
    sessionId: sessionId,
    tool: CliTool.gemini,
    seatMemberId: seatMemberId,
  );
}

void main() {
  test('simple ACP session uses the personal cubit and hides the toggle', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    final personal = _cubit('s1');
    addTearDown(personal.close);
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
      cliTeamName: '',
    )..persistedSession = session;
    tab.acpRuntime = personal;

    expect(
      acpRuntimeForView(session: session, tab: tab, selectedMemberId: ''),
      same(personal),
    );
    expect(hideTerminalToggle(session: session, selectedMemberId: ''), isTrue);
  });

  test('mixed ACP lead uses the lead cubit and hides the toggle', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 'team-1',
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'lead',
          taskId: 'task-lead',
          acp: true,
        ),
        SessionMemberBinding(rosterMemberId: 'worker', taskId: 'task-worker'),
      ],
    );
    final lead = _cubit('s1', seatMemberId: 'lead');
    addTearDown(lead.close);
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
      cliTeamName: 'team-1',
    )..persistedSession = session;
    tab.memberAcpRuntimes['lead'] = lead;

    expect(
      acpRuntimeForView(session: session, tab: tab, selectedMemberId: 'lead'),
      same(lead),
    );
    expect(
      hideTerminalToggle(session: session, selectedMemberId: 'lead'),
      isTrue,
    );
  });

  test('mixed PTY worker has no cubit and shows the toggle', () {
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 'team-1',
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'lead',
          taskId: 'task-lead',
          acp: true,
        ),
        SessionMemberBinding(rosterMemberId: 'worker', taskId: 'task-worker'),
      ],
    );
    final lead = _cubit('s1', seatMemberId: 'lead');
    addTearDown(lead.close);
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
      cliTeamName: 'team-1',
    )..persistedSession = session;
    tab.memberAcpRuntimes['lead'] = lead;

    expect(
      acpRuntimeForView(session: session, tab: tab, selectedMemberId: 'worker'),
      isNull,
    );
    expect(
      hideTerminalToggle(session: session, selectedMemberId: 'worker'),
      isFalse,
    );
  });
}
