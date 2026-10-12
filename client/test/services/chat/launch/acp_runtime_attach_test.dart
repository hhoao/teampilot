import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/launch/connect/acp_runtime_attach.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session/shell_launch_spec.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('mixed transcript is per member', () {
    expect(
      acpTranscriptFileName(memberId: 'lead', personal: false),
      'acp-transcript-lead.jsonl',
    );
    expect(
      acpTranscriptFileName(memberId: null, personal: true),
      'acp-transcript.jsonl',
    );
  });

  test(
    'attachMemberAcpRuntime returns false when the seat is not ACP',
    () async {
      final harness = _Harness();
      final session = _mixedSession(acp: false);
      final team = _mixedTeam();
      final member = _lead();

      final handled = await harness.service.attachMemberAcpRuntime(
        _job(session, team, member),
        session,
        (team: team, member: member, cli: CliTool.claude),
      );

      expect(handled, isFalse);
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );

  test(
    'attachMemberAcpRuntime throws when teammate-bus does not map',
    () async {
      final harness = _Harness(
        extra: const {
          'teammate-bus': {'type': 'http'},
        },
      );
      final session = _mixedSession(acp: true);
      final team = _mixedTeam();
      final member = _lead();

      await expectLater(
        harness.service.attachMemberAcpRuntime(
          _job(session, team, member),
          session,
          (team: team, member: member, cli: CliTool.claude),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'ACP teammate-bus MCP did not map to a session server',
          ),
        ),
      );
      expect(harness.tab.memberAcpRuntimes, isEmpty);
      expect(harness.runtime.started, isFalse);
    },
  );
}

class _Harness {
  _Harness({
    this.extra = const {
      'teammate-bus': {'type': 'http', 'url': 'http://127.0.0.1:9/mcp'},
    },
  }) {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) => runtime,
      prepareAcpTeamConnect:
          ({
            required session,
            required team,
            required member,
            required workspace,
            required launchTarget,
            required workingDirectory,
            extraMcpServers,
          }) async {
            return (
              shellLaunch: ShellLaunchSpec(
                plan: LaunchPlan(
                  env: const {'ACP_TEAM_STAGING': 'mixed-lead'},
                  resume: false,
                  taskId: member.id,
                  cliTeamName: team.name,
                  memberConfigDir: '/runtime/s1/claude',
                  resolvedRoots: const [],
                ),
                launchContext: CliLaunchContext(
                  team: team,
                  member: member,
                  workingDirectory: workingDirectory,
                ),
              ),
              warnings: const <String>[],
              remoteCliPath: '',
            );
          },
      acpMemberExtraMcp: ({required session, required member}) => extra,
    );
  }

  final Map<String, Map<String, Object?>> extra;
  final runtime = _RecordingAcpRuntime();
  final tabStore = ChatTabStore(storage: fakeHomeStorage());
  final tab = ChatTab(
    info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
    cliTeamName: '',
  );
  late final SessionLaunchService service;
}

TeamProfile _mixedTeam() => const TeamProfile(
  id: 'team-1',
  name: 'Team',
  teamMode: TeamMode.mixed,
  members: [TeamMemberConfig(id: 'lead', name: 'Lead')],
);

TeamMemberConfig _lead() =>
    const TeamMemberConfig(id: 'lead', name: 'Lead', cli: CliTool.claude);

AppSession _mixedSession({required bool acp}) => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  sessionTeam: 'team-1',
  members: [
    SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 'task-lead',
      cli: CliTool.claude,
      acp: acp,
    ),
  ],
  memberTargets: const {'lead': 'local'},
  createdAt: 1,
);

SessionConnectJob _job(
  AppSession session,
  TeamProfile team,
  TeamMemberConfig member,
) {
  final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
  return SessionConnectJob(
    session: session,
    request: SessionOpenRequest(
      session: session,
      workspace: workspace,
      team: team,
      member: member,
    ),
    generation: 1,
    workspace: workspace,
    team: team,
    member: member,
    reason: LaunchReason.create,
  );
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  bool get isClosed => false;

  @override
  ChatSessionShellFactory get shellFactory =>
      ChatSessionShellFactory(executableResolver: () => '/usr/bin/claude');

  @override
  CliToolRegistry get cliRegistry => CliToolRegistry.builtIn();

  @override
  void updateTabRunning(String tabId) {}

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _RecordingAcpRuntime implements AcpSessionRuntimeApi {
  var started = false;
  List<acpd.McpServer> mcpServers = const [];

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
  }) async {
    started = true;
    this.mcpServers = mcpServers;
  }

  @override
  bool get isStarted => started;

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
