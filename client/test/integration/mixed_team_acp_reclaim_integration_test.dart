@Tags(['integration'])
library;

import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
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
import 'package:teampilot/services/chat/runtime/pty/terminal_reclaim_policy.dart';
import 'package:teampilot/services/chat/runtime/tab_member_reclaim_watch.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

import '../support/in_memory_filesystem.dart';
import '../support/stub_tab_member_materializer.dart';

/// Mixed-team ACP idle-reclaim + restore, wired across the real reclaim watch
/// and the launch-service discard/attach seams.
///
/// A hidden idle `worker-1` ACP seat is discarded by the reclaim watch (cubit
/// torn down, seat marked reclaimed); the member-connect restore path then
/// re-attaches a fresh cubit and clears the reclaimed flag. This exercises the
/// production discard callback (`SessionLaunchService.discardAcpSeat`) through
/// the real `TabMemberReclaimWatch` instead of calling it directly, but keeps
/// the ACP runtime fake so the test does not need a live `claude-agent-acp`
/// adapter (the real-process path is covered by the Claude ACP integration
/// tests once a mixed-ACP harness lands).
void main() {
  test(
    'idle hidden ACP seat is reclaimed and restored on demand',
    () async {
      final harness = _Harness();
      final session = _mixedSession();
      final team = _mixedTeam();
      final member = _worker();
      final resolved = (team: team, member: member, cli: CliTool.claude);
      final job = _restoreJob(session, team, member);
      harness.tab.persistedSession = session;

      // Boot the mixed worker ACP seat.
      final handled = await harness.service.attachMemberAcpRuntime(
        job,
        session,
        resolved,
      );
      expect(handled, isTrue);
      final firstCubit = harness.tab.memberAcpRuntimes['worker-1'];
      expect(firstCubit, isNotNull);

      // Run a turn to completion so the seat idles at the prompt.
      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();
      expect(firstCubit!.state.phase, AcpChatPhase.idle);

      // The reclaim watch (deterministic clock) discards the hidden idle seat.
      var now = DateTime(2026, 8, 9, 12, 0, 0);
      final watch = _watch(harness, () => now);
      watch.tick();
      now = now.add(const Duration(seconds: 5));
      watch.tick();

      expect(
        harness.tab.memberAcpRuntimes.containsKey('worker-1'),
        isFalse,
        reason: 'the idle hidden ACP seat must be discarded',
      );
      expect(harness.tab.reclaimedMemberIds, contains('worker-1'));
      await pumpEventQueue();
      expect(firstCubit.isClosed, isTrue);

      // Restore: the connect funnel re-attaches a fresh cubit and reports
      // `attached`, which clears the reclaimed flag.
      final reattached = await harness.service.attachMemberAcpRuntime(
        job,
        session,
        resolved,
      );
      final secondCubit = harness.tab.memberAcpRuntimes['worker-1'];
      expect(reattached, isTrue);
      expect(secondCubit, isNotNull);
      expect(identical(secondCubit, firstCubit), isFalse);
      expect(secondCubit!.isClosed, isFalse);

      await harness.service.onConnectResult(
        job,
        session,
        resolved,
        ConnectShellResult.attached,
      );
      expect(harness.tab.reclaimedMemberIds, isNot(contains('worker-1')));

      await secondCubit.close();
      watch.dispose();
    },
  );
}

TabMemberReclaimWatch _watch(_Harness harness, DateTime Function() now) {
  return TabMemberReclaimWatch(
    tabStore: harness.tabStore,
    reclaimEnabled: () => true,
    activeTeam: _mixedTeam,
    policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
    onDiscardMember: (_, __) {},
    now: now,
    acpPolicy: () =>
        const TerminalReclaimPolicy(idleAfter: Duration(seconds: 4)),
    onDiscardAcpSeat: harness.service.discardAcpSeat,
  );
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
                  env: const {'ACP_TEAM_STAGING': 'mixed-worker'},
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

  final runtime = _ControllableAcpRuntime();
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
  members: [
    TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    TeamMemberConfig(id: 'worker-1', name: 'Worker', cli: CliTool.claude),
  ],
);

TeamMemberConfig _worker() => const TeamMemberConfig(
  id: 'worker-1',
  name: 'Worker',
  cli: CliTool.claude,
);

AppSession _mixedSession() => AppSession(
  sessionId: 's1',
  workspaceId: 'w1',
  sessionTeam: 'team-1',
  members: const [
    SessionMemberBinding(
      rosterMemberId: 'worker-1',
      taskId: 'task-worker',
      cli: CliTool.claude,
      acp: true,
    ),
  ],
  memberTargets: const {'worker-1': 'local'},
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

class _ControllableAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();

  void add(AcpSessionUpdate update) => updatesController.add(update);

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
  bool get isStarted => true;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

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
