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
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session/shell_launch_spec.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';
import 'package:teampilot/services/chat/team_bus/team_bus.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test(
    'member attach calls onMemberIdle on the transition into idle',
    () async {
      final harness = _Harness();
      final bus = _RecordingBus();
      harness.tab.teamBus = bus;
      final session = _mixedSession();
      final team = _mixedTeam();
      final member = _lead();

      final handled = await harness.service.attachMemberAcpRuntime(
        _memberJob(session, team, member),
        session,
        (team: team, member: member, cli: CliTool.claude),
      );

      final cubit = harness.tab.memberAcpRuntimes['lead'];
      expect(handled, isTrue);
      expect(cubit, isNotNull);
      expect(cubit!.state.phase, AcpChatPhase.ready);
      expect(bus.idleCalls, isEmpty);

      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();

      expect(cubit.state.phase, AcpChatPhase.idle);
      expect(bus.idleCalls, [(memberId: 'lead', fromPtyQuietWatch: false)]);

      harness.runtime.add(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'still here',
          isThought: false,
        ),
      );
      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();

      expect(cubit.state.phase, AcpChatPhase.idle);
      expect(bus.idleCalls, hasLength(1));
      await cubit.close();
    },
  );

  test('member attach ended does not call onMemberIdle', () async {
    final harness = _Harness()..runtime.armExit();
    final bus = _RecordingBus();
    harness.tab.teamBus = bus;
    final session = _mixedSession();
    final team = _mixedTeam();
    final member = _lead();

    await harness.service.attachMemberAcpRuntime(
      _memberJob(session, team, member),
      session,
      (team: team, member: member, cli: CliTool.claude),
    );

    final cubit = harness.tab.memberAcpRuntimes['lead']!;
    expect(cubit.state.phase, AcpChatPhase.ready);
    harness.runtime.completeExit(1);
    await pumpEventQueue();

    expect(cubit.state.phase, AcpChatPhase.ended);
    expect(bus.idleCalls, isEmpty);
    await cubit.close();
  });

  test(
    'personal attachAcpRuntime does not call onMemberIdle when the cubit idles',
    () async {
      final harness = _Harness();
      final bus = _RecordingBus();
      harness.tab.teamBus = bus;
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.claude,
        acp: true,
        createdAt: 1,
      );
      final workspace = Workspace(workspaceId: 'w1', createdAt: 1);

      await harness.service.attachAcpRuntime(
        SessionConnectJob(
          session: session,
          request: SessionOpenRequest(session: session, workspace: workspace),
          generation: 1,
          workspace: workspace,
          reason: LaunchReason.create,
        ),
        session,
      );

      final cubit = harness.tab.acpRuntime!;
      expect(cubit.state.phase, AcpChatPhase.ready);
      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();

      expect(cubit.state.phase, AcpChatPhase.idle);
      expect(bus.idleCalls, isEmpty);
      await cubit.close();
    },
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

  final runtime = _ControllableAcpRuntime();
  final tabStore = ChatTabStore(storage: fakeHomeStorage());
  final tab = ChatTab(
    info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
    cliTeamName: '',
  );
  late final SessionLaunchService service;
}

class _RecordingBus implements TeamBus {
  final idleCalls = <({String memberId, bool fromPtyQuietWatch})>[];

  @override
  void onMemberIdle(String memberId, {bool fromPtyQuietWatch = false}) {
    idleCalls.add((memberId: memberId, fromPtyQuietWatch: fromPtyQuietWatch));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

SessionConnectJob _memberJob(
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

class _ControllableAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  Completer<int>? _agentExit;
  var started = false;

  void add(AcpSessionUpdate update) => updatesController.add(update);

  void armExit() => _agentExit = Completer<int>();

  void completeExit(int code) => _agentExit?.complete(code);

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
  }

  @override
  bool get isStarted => started;

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
  Future<int>? get agentProcessExitCode => _agentExit?.future;

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
