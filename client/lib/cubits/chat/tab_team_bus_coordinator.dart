import 'dart:async';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/bus_user_line_capture.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../services/team_bus/persistence/bus_message_log_factory.dart';
import '../../services/team_bus/tasks/task_log_factory.dart';
import '../../services/team_bus/tasks/task_queue.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../utils/team_member_naming.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Edge ChatCubit must implement so the coordinator can drive member connects
/// from the bus (materialize) path.
abstract interface class MemberConnector {
  void scheduleMemberConnect(
    TeamConfig team,
    TeamMemberConfig member,
    ChatTab tab,
  );
}

/// Owns per-tab TeamBus + MCP server lifecycle and the cross-tab idle watch.
/// Implements [MemberMaterializer] (was ChatCubit's role).
class TabTeamBusCoordinator implements MemberMaterializer {
  TabTeamBusCoordinator({
    required ChatTabStore tabStore,
    required ChatSessionShellFactory shellFactory,
    required MemberConnector connector,
    required TeamConfig? Function() activeTeam,
    required bool Function() isClosed,
  })  : _tabStore = tabStore,
        _shellFactory = shellFactory,
        _connector = connector,
        _activeTeam = activeTeam,
        _isClosed = isClosed;

  final ChatTabStore _tabStore;
  final ChatSessionShellFactory _shellFactory;
  final MemberConnector _connector;
  final TeamConfig? Function() _activeTeam;
  final bool Function() _isClosed;

  final Map<(String, String), Completer<void>> _memberReady = {};
  Timer? _idleWatchTimer;
  final Map<String, bool> _lastWorking = {};

  Future<void> installBusForTab(
    ChatTab tab,
    TeamConfig team,
    AppSession session,
  ) async {
    // 共享任务队列仅 mixed 模式接线：纯 Claude swarm 复用 Claude 原生任务表。
    final taskQueue = team.teamMode == TeamMode.mixed
        ? TaskQueue(log: TaskLogFactory.forSession(session.sessionId))
        : null;
    final bus = TeamBus(
      launcher: ChatCubitMemberLauncher(
        materializer: this,
        sessionId: tab.info.id,
      ),
      messageLog: BusMessageLogFactory.forSession(session.sessionId),
      taskQueue: taskQueue,
    );
    final cliTeamName = session.cliTeamName;
    bus.installSessionContext(
      TeamSessionContext(
        cliTeamName: cliTeamName,
        teamId: team.id,
        teamName: team.name,
        description: team.description,
        workingDirectory: session.primaryPath,
        teamMode: team.teamMode.value,
        leadAgentId: TeamMemberNaming.leadAgentId(cliTeamName),
        appSessionId: session.sessionId,
        additionalPaths: session.additionalPaths,
      ),
    );
    for (final m in team.members) {
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
            cwd: session.primaryPath,
            taskId: taskId,
          ),
          lifecycle: MemberLifecycle.declared,
        ),
      );
    }
    await bus.rehydrateUnread();
    final server = TeammateBusMcpServer(
      handler: TeammateBusMcpHandler(bus: bus),
    );
    await server.start();
    tab.teamBus = bus;
    tab.mcpServer = server;
    ensureIdleWatch();
  }

  BusUserInputRouting? busUserInputRouting(
    ChatTab tab,
    TeamConfig team,
    TeamMemberConfig member,
  ) {
    final bus = tab.teamBus;
    if (team.teamMode != TeamMode.mixed || bus == null) return null;
    final memberId = member.id;
    return BusUserInputRouting(
      shouldIntercept: () => bus.isWaitingForMessage(memberId),
      onUserLine: (line) => bus.deliverUserCommand(memberId, line),
    );
  }

  void markMemberReady(String sessionId, String memberId) {
    _memberReady.remove((sessionId, memberId))?.complete();
  }

  @override
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  ) async {
    final tab = _tabStore.bySessionId(sessionId);
    final team = _activeTeam();
    if (tab == null || team == null) return;
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) return;
    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;
    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      ready.complete();
    } else {
      _connector.scheduleMemberConnect(team, member, tab);
    }
    await ready.future;
  }

  @override
  void injectMemberStdin(String sessionId, String memberId, String text) {
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final team = _activeTeam();
    final cli = team == null
        ? TeamCli.flashskyai
        : _shellFactory.cliForMember(team, memberId);
    if (cli.usesFullScreenInput) {
      unawaited(shell.submitFullScreenInput(trimmed));
    } else {
      shell.writeln(trimmed);
    }
  }

  void ensureIdleWatch() {
    if (_idleWatchTimer != null) return;
    _idleWatchTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickIdleWatch(),
    );
  }

  void maybeStopIdleWatch() {
    final anyBus = _tabStore.tabs.any((t) => t.teamBus != null);
    if (!anyBus) {
      _idleWatchTimer?.cancel();
      _idleWatchTimer = null;
      _lastWorking.clear();
    }
  }

  void disposeIdleWatch() {
    _idleWatchTimer?.cancel();
    _idleWatchTimer = null;
    _lastWorking.clear();
  }

  bool hasTeamBusResources(String sessionId) {
    final tab = _tabStore.bySessionId(sessionId);
    return tab?.teamBus != null && tab?.mcpServer != null;
  }

  Uri? teammateBusMcpEndpointForSession(String sessionId) {
    final server = _tabStore.bySessionId(sessionId)?.mcpServer;
    if (server == null) return null;
    try {
      return server.endpoint;
    } catch (_) {
      return null;
    }
  }

  void _tickIdleWatch() {
    if (_isClosed()) return;
    for (final tab in _tabStore.tabs) {
      final bus = tab.teamBus;
      if (bus == null) continue;
      // 租约回收：claimed 超时且认领者掉线的任务退回 pending（仅 mixed 模式有队列）。
      if (bus.hasTaskQueue) bus.reclaimExpiredTasks();
      tab.memberShells.forEach((memberId, shell) {
        final key = '${tab.info.id}:$memberId';
        final working = shell.activityTracker.isWorking;
        final was = _lastWorking[key] ?? false;
        _lastWorking[key] = working;
        if (was && !working && !bus.isWaitingForMessage(memberId)) {
          bus.onMemberIdle(memberId);
        }
      });
    }
  }
}
