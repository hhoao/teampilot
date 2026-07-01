import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/team/member_turn_idle_sync.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../../services/team_bus/bus_user_line_capture.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../services/team_bus/persistence/bus_message_log_factory.dart';
import '../../services/team_bus/tasks/task_log_factory.dart';
import '../../services/team_bus/tasks/task_queue.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../utils/logger.dart';
import '../../utils/team_member_naming.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Edge ChatCubit must implement so the coordinator can drive member connects
/// from the bus (materialize) path.
abstract interface class MemberConnector {
  void scheduleMemberConnect(
    TeamProfile team,
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
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
    required List<CliPreset> Function() globalPresets,
    void Function(Set<String> workingSessionIds)? onWorkingSessionsChanged,
    VoidCallback? onAfterIdleWatchTick,
    ArtifactTransferService Function(AppSession session)? artifactServiceFactory,
  })  : _tabStore = tabStore,
        _shellFactory = shellFactory,
        _connector = connector,
        _globalPresets = globalPresets,
        _activeTeam = activeTeam,
        _isClosed = isClosed,
        _onWorkingSessionsChanged = onWorkingSessionsChanged,
        _onAfterIdleWatchTick = onAfterIdleWatchTick,
        _artifactServiceFactory = artifactServiceFactory;

  final ChatTabStore _tabStore;
  final ChatSessionShellFactory _shellFactory;
  final MemberConnector _connector;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final bool Function() _isClosed;
  final void Function(Set<String> workingSessionIds)? _onWorkingSessionsChanged;
  final VoidCallback? _onAfterIdleWatchTick;

  /// P3d: builds the per-session cross-machine artifact transfer service. Null =
  /// the three artifact MCP tools are not advertised (single-machine / tests).
  final ArtifactTransferService Function(AppSession session)?
      _artifactServiceFactory;
  Set<String> _lastWorkingSessions = const {};

  final Map<(String, String), Completer<void>> _memberReady = {};
  Timer? _idleWatchTimer;

  /// Per-member rising edge of in-turn (`userTurnActive` or bus `active`).
  final Map<String, bool> _wasInTurn = {};

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
        ? TaskQueue(log: TaskLogFactory.forSession(session.workspaceId, session.sessionId))
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
        materializer: this,
        sessionId: tab.info.id,
      ),
      messageLog: BusMessageLogFactory.forSession(session.workspaceId, session.sessionId),
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
    final server = TeammateBusMcpServer(
      handler: TeammateBusMcpHandler(
        bus: bus,
        artifacts: _artifactServiceFactory?.call(session),
        forceWaitBeforeStop: team.forceWaitBeforeStop,
        // 成员级解析：cursor 等 push-投递 CLI → false（正常停 + 门铃投递）。
        forceWaitForMember: (memberId) =>
            forceWaitByMember[memberId] ?? team.forceWaitBeforeStop,
      ),
    );
    await server.start();
    tab.teamBus = bus;
    tab.mcpServer = server;
    ensureIdleWatch();
    appLogger.d(
      '[session-launch] installBusForTab ready '
      'session=${session.sessionId} endpoint=${server.endpoint}',
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
      },
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
        ? CliTool.claude
        : _shellFactory.cliForMember(
            team,
            memberId,
            globalPresets: _globalPresets(),
          );
    final usesFullScreen =
        CliToolRegistry.builtIn()
            .capability<TerminalBehaviorCapability>(cli)
            ?.usesFullScreenInput ??
        false;
    if (usesFullScreen) {
      unawaited(shell.submitFullScreenInput(trimmed));
    } else {
      shell.writeln(trimmed);
    }
  }

  @override
  void submitMemberPending(String sessionId, String memberId) {
    // 门铃重试：只补回车，提交已卡在框里的上一条提示，绝不重打全文（见
    // [MemberLauncher.nudgeSubmit]）。CR-only 在全屏 / 普通 CLI 都安全（空 prompt
    // 上回车是 no-op）。
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) return;
    unawaited(shell.submitPendingCr());
  }

  void ensureIdleWatch() {
    if (_idleWatchTimer != null) return;
    _idleWatchTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickIdleWatch(),
    );
  }

  void maybeStopIdleWatch() {
    // 任何打开的 tab（含简单 / 原生单 CLI）都靠该看门狗驱动 working 指示器，
    // 故仅在全部关闭后才停表。
    if (_tabStore.tabs.isEmpty) {
      _idleWatchTimer?.cancel();
      _idleWatchTimer = null;
      _wasInTurn.clear();
      _publishWorkingSessions(const {}); // no tabs left → nothing spins.
    }
  }

  void disposeIdleWatch() {
    _idleWatchTimer?.cancel();
    _idleWatchTimer = null;
    _wasInTurn.clear();
    _publishWorkingSessions(const {});
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

  /// Test seam: synchronously run one idle-watch tick (exposed through
  /// `ChatCubit.debugTickIdleWatch`).
  void debugTickIdleWatch() => _tickIdleWatch();

  void _tickIdleWatch() {
    if (_isClosed()) return;
    final working = <String>{};
    for (final tab in _tabStore.tabs) {
      final bus = tab.teamBus;
      if (bus != null) {
        if (bus.hasTaskQueue) bus.reclaimExpiredTasks();
        bus.reengageIdleWorkers();
      }
      var tabWorking = false;
      tab.memberShells.forEach((memberId, shell) {
        final key = '${tab.info.id}:$memberId';
        final inTurn = bus != null
            ? bus.isMemberInTurn(memberId)
            : shell.userTurnActive;
        final stillWorking = MemberTurnIdleSync.tick(
          turnKey: key,
          inTurn: inTurn,
          shell: shell,
          wasInTurn: _wasInTurn,
          endTurn: () {
            if (bus != null) {
              bus.onMemberIdle(memberId);
            } else {
              shell.markUserTurnIdle();
            }
          },
        );
        if (stillWorking) tabWorking = true;
      });
      if (bus != null) {
        if (bus.anyMemberInTurn) working.add(tab.info.id);
      } else if (tabWorking) {
        working.add(tab.info.id);
      }
    }
    _publishWorkingSessions(working);
    _onAfterIdleWatchTick?.call();
  }

  /// Emits the session-level working set (only when changed) so tabs / sidebar
  /// can spin. Computed right after the idle edges above so it reflects this
  /// tick's transitions.
  void _publishWorkingSessions(Set<String> working) {
    final cb = _onWorkingSessionsChanged;
    if (cb == null) return;
    if (setEquals(working, _lastWorkingSessions)) return;
    _lastWorkingSessions = working;
    cb(working);
  }
}
