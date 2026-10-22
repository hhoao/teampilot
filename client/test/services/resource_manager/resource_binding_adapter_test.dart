import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/resource_manager/resource_binding_adapter.dart';

const _testStrings = AcpChatStrings(
  launchFailedVersion: 'v',
  launchFailedAdapter: 'a',
  launchFailed: 'l',
  turnFailed: 't',
  processExited: 'x',
  notLoggedIn: 'Not logged in',
);

/// All-stub runtime that also advertises the local process pid capability.
class _PidRuntime implements AcpSessionRuntimeApi, AcpAgentProcessPidApi {
  _PidRuntime(this.agentPid);

  @override
  final int? agentPid;

  @override
  bool get isStarted => false;

  @override
  String get sessionId => 'acp-1';

  @override
  AcpAuthNotice? lastAuthNotice;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      const Stream.empty();

  @override
  Stream<AcpPendingClientRequest> get clientRequests => const Stream.empty();

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
    String? resumeSessionId,
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  Future<void> prompt(String text) async {}

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

AcpChatRuntimeCubit _cubit(int? pid) => AcpChatRuntimeCubit(
  runtime: _PidRuntime(pid),
  sessionId: 's1',
  tool: CliTool.gemini,
)..ensureStrings(_testStrings);

void main() {
  test('collects a live personal ACP seat keyed by tab id + map key', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'ACP', subtitle: ''),
      cliTeamName: '',
    );
    tab.persistedSession = AppSession(
      sessionId: 's1',
      workspaceId: 'ws1',
      acp: true,
      createdAt: 1,
    );
    tab.acpRuntime = _cubit(4242);

    final refs = acpSeatRefsForWorkspace(
      workspaceId: 'ws1',
      tabs: [tab],
      sessionTitle: (_) => 'ACP',
      memberName: (_, __) => '',
    );

    expect(refs, hasLength(1));
    expect(refs.single.sessionId, 's1');
    expect(refs.single.memberId, 's1');
    expect(refs.single.workspaceId, 'ws1');
    expect(refs.single.livePid, 4242);
  });

  test('collects mixed-seat ACP runtimes keyed by roster member id', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'Team', subtitle: ''),
      cliTeamName: '',
    );
    tab.workspaceId = 'ws1';
    tab.memberAcpRuntimes['lead'] = _cubit(7);
    tab.memberAcpRuntimes['dev'] = _cubit(null);

    final refs = acpSeatRefsForWorkspace(
      workspaceId: 'ws1',
      tabs: [tab],
      sessionTitle: (_) => 'Team',
      memberName: (_, id) => id.toUpperCase(),
    );

    expect(refs.map((r) => r.memberId).toSet(), {'lead', 'dev'});
    expect(refs.firstWhere((r) => r.memberId == 'dev').livePid, isNull);
  });

  test('skips a closed ACP seat', () async {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'ACP', subtitle: ''),
      cliTeamName: '',
    );
    tab.workspaceId = 'ws1';
    final cubit = _cubit(1);
    tab.acpRuntime = cubit;
    await cubit.close();

    final refs = acpSeatRefsForWorkspace(
      workspaceId: 'ws1',
      tabs: [tab],
      sessionTitle: (_) => 'ACP',
      memberName: (_, __) => '',
    );

    expect(refs, isEmpty);
  });

  test('skips tabs from other workspaces', () {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'ACP', subtitle: ''),
      cliTeamName: '',
    );
    tab.workspaceId = 'ws1';
    tab.acpRuntime = _cubit(1);

    final refs = acpSeatRefsForWorkspace(
      workspaceId: 'ws2',
      tabs: [tab],
      sessionTitle: (_) => 'ACP',
      memberName: (_, __) => '',
    );

    expect(refs, isEmpty);
  });
}
