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
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/connect/connect_shell_result.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session/shell_launch_spec.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/stub_tab_member_materializer.dart';

/// Non-integration regression guard for the mixed-ACP idle-reclaim restore
/// contract: `discardAcpSeat` tears the seat down and marks it reclaimed; the
/// existing member-connect funnel then re-attaches the seat (fresh cubit) and
/// `onConnectResult(attached)` clears the reclaimed flag. This mirrors, at the
/// smallest runnable seams, the executor sequence
/// `attachMemberAcpRuntime` → `onResult(ConnectShellResult.attached)` that the
/// production `ensureMemberTerminalForView` restore path drives.
void main() {
  test(
    'discarded mixed ACP seat re-attaches and clears the reclaimed flag',
    () async {
      final harness = _Harness();
      final session = _mixedSession();
      final team = _mixedTeam();
      final member = _lead();
      final resolved = (team: team, member: member, cli: CliTool.claude);
      final job = _restoreJob(session, team, member);

      // Initial attach (create path) populates the mixed seat runtime.
      final firstHandled = await harness.service.attachMemberAcpRuntime(
        job,
        session,
        resolved,
      );
      final firstCubit = harness.tab.memberAcpRuntimes['lead'];
      expect(firstHandled, isTrue);
      expect(firstCubit, isNotNull);

      // Idle reclaim discards the seat: cubit removed, seat marked reclaimed.
      harness.service.discardAcpSeat('s1', 'lead');
      expect(harness.tab.memberAcpRuntimes.containsKey('lead'), isFalse);
      expect(harness.tab.reclaimedMemberIds, contains('lead'));

      await pumpEventQueue();
      expect(firstCubit!.isClosed, isTrue);

      // Restore: the member-connect funnel re-attaches a *fresh* cubit because
      // the discarded seat was removed from `memberAcpRuntimes`.
      final secondHandled = await harness.service.attachMemberAcpRuntime(
        job,
        session,
        resolved,
      );
      final secondCubit = harness.tab.memberAcpRuntimes['lead'];
      expect(secondHandled, isTrue);
      expect(secondCubit, isNotNull);
      expect(identical(secondCubit, firstCubit), isFalse);
      expect(secondCubit!.isClosed, isFalse);

      // The executor reports the attach result; the reclaimed flag clears.
      await harness.service.onConnectResult(
        job,
        session,
        resolved,
        ConnectShellResult.attached,
      );
      expect(
        harness.tab.reclaimedMemberIds,
        isNot(contains('lead')),
        reason: 'an attached restore must clear the reclaimed seat flag',
      );

      await secondCubit.close();
    },
  );

  test('onConnectResult leaves the flag set for non-attached results', () async {
    final harness = _Harness();
    final session = _mixedSession();
    final team = _mixedTeam();
    final member = _lead();
    final job = _restoreJob(session, team, member);
    harness.tab.reclaimedMemberIds.add('lead');

    await harness.service.onConnectResult(
      job,
      session,
      (team: team, member: member, cli: CliTool.claude),
      ConnectShellResult.failed,
    );

    expect(
      harness.tab.reclaimedMemberIds,
      contains('lead'),
      reason: 'a failed connect must not clear the reclaimed flag',
    );
  });
}

class _Harness {
  _Harness() {
    tabStore.setActiveWorkspaceId('w1');
    tabStore.registerSession(tab);
    service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
      acpRuntimeFactory: ({required logger, required tool}) => runtime,
      prepareAcpContribution: (session, workspace) async => const {},
      prepareAcpTeamConnect:
          ({
            required session,
            required team,
            required member,
            required workspace,
            required launchTarget,
            required workingDirectory,
            extraMcpServers,
            agentStatus,
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
      acpMemberExtraMcp: ({required session, required member}) => const {
        'teammate-bus': {'type': 'http', 'url': 'http://127.0.0.1:9/mcp'},
      },
    );
  }

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

AppSession _mixedSession() => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  sessionTeam: 'team-1',
  members: const [
    SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 'task-lead',
      cli: CliTool.claude,
      acp: true,
    ),
  ],
  memberTargets: const {'lead': 'local'},
  createdAt: 1,
);

SessionConnectJob _restoreJob(
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
    reason: LaunchReason.restore,
  );
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore) : memberMaterializer = stubTabMemberMaterializer(tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

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
  void clearLaunchError(String sessionId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _RecordingAcpRuntime implements AcpSessionRuntimeApi {
  var started = false;

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
  }) async {
    started = true;
  }

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

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
