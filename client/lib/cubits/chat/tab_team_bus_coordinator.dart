import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../../services/team_bus/bus_user_line_capture.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/persistence/bus_message_log_factory.dart';
import '../../services/team_bus/roster_machine.dart';
import '../../services/team_bus/tasks/task_log_factory.dart';
import '../../services/team_bus/tasks/task_queue.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Mixed-mode TeamBus + MCP gateway lifecycle for a session tab.
class TabTeamBusCoordinator {
  TabTeamBusCoordinator({
    required TeammateBusMcpGateway gateway,
    required ChatTabStore tabStore,
    required MemberMaterializer materializer,
    required List<CliPreset> Function() globalPresets,
    required RuntimeTarget Function(AppSession session, {String? memberId})
    launchWorkTarget,
    required ({String workingDirectory, List<String> addDirs}) Function(
      AppSession session,
      String memberId,
    )
    memberWorkDirs,
    SshProfile? Function(String profileId)? sshProfileById,
    void Function()? onAfterTurnLatched,
    ArtifactTransferService Function(AppSession session)?
    artifactServiceFactory,
  }) : _gateway = gateway,
       _tabStore = tabStore,
       _materializer = materializer,
       _globalPresets = globalPresets,
       _launchWorkTarget = launchWorkTarget,
       _memberWorkDirs = memberWorkDirs,
       _sshProfileById = sshProfileById,
       _onAfterTurnLatched = onAfterTurnLatched,
       _artifactServiceFactory = artifactServiceFactory;

  final TeammateBusMcpGateway _gateway;
  final ChatTabStore _tabStore;
  final MemberMaterializer _materializer;
  final List<CliPreset> Function() _globalPresets;
  final RuntimeTarget Function(AppSession session, {String? memberId})
  _launchWorkTarget;
  final ({String workingDirectory, List<String> addDirs}) Function(
    AppSession session,
    String memberId,
  )
  _memberWorkDirs;
  final SshProfile? Function(String profileId)? _sshProfileById;
  final void Function()? _onAfterTurnLatched;

  /// P3d: builds the per-session cross-machine artifact transfer service. Null =
  /// the three artifact MCP tools are not advertised (single-machine / tests).
  final ArtifactTransferService Function(AppSession session)?
  _artifactServiceFactory;

  Future<void> installBusForTab(
    ChatTab tab,
    TeamProfile team,
    AppSession session,
  ) async {
    final runtimeMembers = sessionRosterMembers(session, team);
    final memberCount = runtimeMembers.length;
    appLogger.d(
      '[session-launch] installBusForTab start '
      'session=${session.sessionId} team=${team.id} '
      'teamMode=${team.teamMode.name} members=$memberCount',
    );
    // 共享任务队列仅 mixed 模式接线：纯 Claude swarm 复用 Claude 原生任务表。
    final taskQueue = team.teamMode == TeamMode.mixed
        ? TaskQueue(
            log: TaskLogFactory.forSession(
              session.workspaceId,
              session.sessionId,
            ),
          )
        : null;
    final presets = _globalPresets();
    final forceWaitByMember = {
      for (final m in runtimeMembers)
        m.id: m.effectiveForceWaitBeforeStop(
          team,
          launchCli: memberLaunchCli(
            team: team,
            member: m,
            globalPresets: presets,
          ),
        ),
    };
    final bus = TeamBus(
      launcher: ChatCubitMemberLauncher(
        materializer: _materializer,
        sessionId: tab.info.id,
      ),
      messageLog: BusMessageLogFactory.forSession(
        session.workspaceId,
        session.sessionId,
      ),
      taskQueue: taskQueue,
      reportsIdleViaReceiveWork: (memberId) =>
          forceWaitByMember[memberId] ?? team.forceWaitBeforeStop,
    );
    final cliTeamName = session.cliTeamName;
    bus.installSessionContext(
      TeamSessionContext(
        cliTeamName: cliTeamName,
        teamId: team.id,
        teamName: team.name,
        description: team.description,
        workingDirectory: session.firstFolderPath,
        teamMode: team.teamMode.value,
        leadAgentId: TeamMemberNaming.leadAgentId(cliTeamName),
        appSessionId: session.sessionId,
        additionalPaths: session.extraFolderPaths,
      ),
    );
    for (final m in runtimeMembers) {
      final taskId = session.members
          .where((b) => b.rosterMemberId == m.id)
          .map((b) => b.taskId)
          .where((id) => id.isNotEmpty)
          .firstOrNull;
      final target = _launchWorkTarget(session, memberId: m.id);
      final profileId = target.sshProfileId ?? sshProfileIdOfId(target.id);
      final ssh = (profileId != null && profileId.isNotEmpty)
          ? _sshProfileById?.call(profileId)
          : null;
      final rosterMachine = rosterMachineFromTarget(target, profile: ssh);
      final work = _memberWorkDirs(session, m.id);
      bus.declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: m,
            team: team,
            cliTeamName: cliTeamName,
            cwd: work.workingDirectory,
            taskId: taskId,
            globalPresets: presets,
            machine: rosterMachine.machine,
            machineKind: rosterMachine.machineKind,
            machineId: rosterMachine.machineId,
          ),
          lifecycle: MemberLifecycle.declared,
        ),
      );
    }
    await bus.rehydrateUnread();
    await _gateway.ensureStarted();
    final handler = TeammateBusMcpHandler(
      bus: bus,
      artifacts: _artifactServiceFactory?.call(session),
      forceWaitBeforeStop: team.forceWaitBeforeStop,
      // 成员级解析：cursor 等 push-投递 CLI → false（正常停 + 门铃投递）。
      forceWaitForMember: (memberId) =>
          forceWaitByMember[memberId] ?? team.forceWaitBeforeStop,
    );
    final reg = _gateway.register(
      sessionId: session.sessionId,
      handler: handler,
    );
    tab.teamBus = bus;
    tab.busSessionRegistration = reg;
    appLogger.d(
      '[session-launch] installBusForTab ready '
      'session=${session.sessionId} endpoint=${_gateway.mcpEndpoint}',
    );
  }

  BusUserInputRouting? busUserInputRouting(
    ChatTab tab,
    TeamProfile team,
    TeamMemberConfig member,
  ) {
    final bus = tab.teamBus;
    if (team.teamMode != TeamMode.mixed || bus == null) return null;
    final memberId = member.id;
    final shell = tab.memberShells[memberId];
    return BusUserInputRouting(
      shouldIntercept: () => bus.isWaitingForMessage(memberId),
      onUserLine: (line) => bus.deliverUserCommand(memberId, line),
      isUnread: (id) => bus.isUnread(memberId, id),
      onTurnStart: () {
        shell?.activityTracker.latchTurnQuietBaseline();
        bus.markTurnStarted(memberId);
        _onAfterTurnLatched?.call();
      },
    );
  }

  TeamBus? busForSession(String sessionId) =>
      _tabStore.openTabBySessionId(sessionId)?.teamBus;

  bool hasTeamBusResources(String sessionId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
    return tab?.teamBus != null && _gateway.isSessionRegistered(sessionId);
  }

  Uri? teammateBusMcpEndpointForSession(String sessionId) {
    if (!_gateway.isSessionRegistered(sessionId)) return null;
    return _gateway.mcpEndpoint;
  }

  Future<void> disposeSessionBus(String sessionId) async {
    await _gateway.unregister(sessionId);
  }
}
