import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/config_profile/config_profile_context.dart';
import '../../services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../../services/team_bus/bus_user_line_capture.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/member_bus_idle_endpoint.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/persistence/bus_message_log_factory.dart';
import '../../services/team_bus/tasks/task_log_factory.dart';
import '../../services/team_bus/tasks/task_queue.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../utils/logger.dart';
import '../../utils/team_member_naming.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Mixed-mode TeamBus + MCP gateway lifecycle for a session tab.
class TabTeamBusCoordinator {
  TabTeamBusCoordinator({
    required TeammateBusMcpGateway gateway,
    required ChatTabStore tabStore,
    required MemberMaterializer materializer,
    required List<CliPreset> Function() globalPresets,
    void Function()? onAfterTurnLatched,
    ArtifactTransferService Function(AppSession session)?
    artifactServiceFactory,
    CliToolRegistry? cliRegistry,
    Future<ConfigProfileDelegate> Function(AppSession session)?
    resolveLifecyclePaths,
  }) : _gateway = gateway,
       _tabStore = tabStore,
       _materializer = materializer,
       _globalPresets = globalPresets,
       _onAfterTurnLatched = onAfterTurnLatched,
       _artifactServiceFactory = artifactServiceFactory,
       _cliRegistry = cliRegistry,
       _resolveLifecyclePaths = resolveLifecyclePaths;

  final TeammateBusMcpGateway _gateway;
  final ChatTabStore _tabStore;
  final MemberMaterializer _materializer;
  final List<CliPreset> Function() _globalPresets;
  final void Function()? _onAfterTurnLatched;

  /// P3d: builds the per-session cross-machine artifact transfer service. Null =
  /// the three artifact MCP tools are not advertised (single-machine / tests).
  final ArtifactTransferService Function(AppSession session)?
  _artifactServiceFactory;
  final CliToolRegistry? _cliRegistry;
  final Future<ConfigProfileDelegate> Function(AppSession session)?
  _resolveLifecyclePaths;

  Future<void> _invalidateStaleCursorOverlay({
    required TeamProfile team,
    required AppSession session,
  }) async {
    if (team.teamMode != TeamMode.mixed) return;
    final registry = _cliRegistry;
    final resolvePaths = _resolveLifecyclePaths;
    if (registry == null || resolvePaths == null) return;

    final lifecycle = registry.lifecycleFor(CliTool.cursor);
    if (lifecycle is! CursorSessionLifecycleCapability) return;

    final paths = await resolvePaths(session);
    final busIdle = MemberBusIdleEndpoint.local(
      _gateway,
      sessionId: session.sessionId,
    );
    final cursorLifecycle = lifecycle;
    await cursorLifecycle.onBusEndpointChanged(
      workspaceId: session.workspaceId,
      sessionId: session.sessionId,
      paths: paths,
      busIdle: busIdle,
    );
  }

  Future<void> installBusForTab(
    ChatTab tab,
    TeamProfile team,
    AppSession session,
  ) async {
    final runtimeMembers = runtimeRosterMembers(team);
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
      bus.declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: m,
            team: team,
            cliTeamName: cliTeamName,
            cwd: session.firstFolderPath,
            taskId: taskId,
            globalPresets: presets,
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
    await _invalidateStaleCursorOverlay(
      team: team,
      session: session,
    );
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
      _tabStore.bySessionId(sessionId)?.teamBus;

  bool hasTeamBusResources(String sessionId) {
    final tab = _tabStore.bySessionId(sessionId);
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
