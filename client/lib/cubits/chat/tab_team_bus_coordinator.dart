import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/capabilities/presence_capability.dart';
import '../../services/team/member_availability_resolver.dart';
import '../../services/team/member_turn_idle_sync.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/artifacts/artifact_transfer_service.dart';
import '../../services/team_bus/bus_user_line_capture.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/persistence/bus_message_log_factory.dart';
import '../../services/team_bus/tasks/task_log_factory.dart';
import '../../services/team_bus/tasks/task_queue.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../services/terminal/fullscreen_cr_ack_config.dart';
import '../../services/terminal/member_pty_inject_service.dart';
import '../../services/terminal/pty_automation_delivery_guard.dart';
import '../../services/terminal/pty_automation_retry_queue.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/terminal/terminal_session.dart';
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
    required TeammateBusMcpGateway gateway,
    required ChatTabStore tabStore,
    required ChatSessionShellFactory shellFactory,
    required MemberConnector connector,
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
    required List<CliPreset> Function() globalPresets,
    void Function(Set<String> workingSessionIds)? onWorkingSessionsChanged,
    VoidCallback? onAfterIdleWatchTick,
    ArtifactTransferService Function(AppSession session)?
    artifactServiceFactory,
  }) : _gateway = gateway,
       _tabStore = tabStore,
       _shellFactory = shellFactory,
       _connector = connector,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _isClosed = isClosed,
       _onWorkingSessionsChanged = onWorkingSessionsChanged,
       _onAfterIdleWatchTick = onAfterIdleWatchTick,
       _artifactServiceFactory = artifactServiceFactory;

  final TeammateBusMcpGateway _gateway;
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

  final MemberPtyInjectService _ptyInject = MemberPtyInjectService();

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
        materializer: this,
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
    ensureIdleWatch();
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
      },
    );
  }

  void markMemberReady(String sessionId, String memberId) {
    _memberReady.remove((sessionId, memberId))?.complete();
  }

  /// PTY connect + TUI/agent startup complete — used before automation inject.
  ///
  /// [directToPty]: compose-landing operator input — boot frame only, inject at
  /// the TUI prompt (never wait for bus `wait_for_message`).
  Future<void> ensureMemberInputReady(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) async {
    await materializeMember(sessionId, memberId, '');
    while (!_isClosed()) {
      if (_isMemberReadyForAutomationInput(
        sessionId,
        memberId,
        directToPty: directToPty,
      )) {
        appLogger.d(
          '[team-bus] input-ready member=$memberId session=$sessionId '
          'directToPty=$directToPty',
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  bool _isMemberReadyForAutomationInput(
    String sessionId,
    String memberId, {
    bool directToPty = false,
  }) {
    final tab = _tabStore.bySessionId(sessionId);
    if (tab == null) return false;
    final shell = tab.memberShells[memberId];
    if (shell == null || !shell.isConnected) return false;

    final session = tab.persistedSession;
    final isPersonal = session == null || session.sessionTeam.trim().isEmpty;
    final globalPresets = _globalPresets();

    if (isPersonal) {
      return MemberAvailabilityResolver.isReadyForAutomationInput(
        shell: shell,
        member: TeamMemberConfig(id: memberId, name: memberId),
        team: const TeamProfile(id: '', name: ''),
        teamMode: TeamMode.native,
        globalPresets: globalPresets,
        bus: null,
        claudeRosterWorking: false,
        usesClaudeRoster: false,
        usesShellActivity: true,
      );
    }

    final team = _activeTeam();
    if (directToPty) {
      // Team runtime may still be wiring [activeTeam] while the tab connects;
      // landing only needs a connected shell past the boot frame.
      if (team == null) {
        return shell.activityTracker.isBootFrameReady;
      }
      final member = team.members.firstWhere(
        (m) => m.id == memberId,
        orElse: () => const TeamMemberConfig(id: '', name: ''),
      );
      if (!member.isValid) return shell.activityTracker.isBootFrameReady;

      final presenceCap = CliToolRegistry.builtIn()
          .capability<PresenceCapability>(team.cli);
      return MemberAvailabilityResolver.isReadyForAutomationInput(
        shell: shell,
        member: member,
        team: team,
        teamMode: TeamMode.native,
        globalPresets: globalPresets,
        bus: null,
        claudeRosterWorking: false,
        usesClaudeRoster: presenceCap?.usesClaudeRoster ?? false,
        usesShellActivity: presenceCap?.usesShellActivity ?? false,
      );
    }
    if (team == null) return false;
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) return false;

    final presenceCap = CliToolRegistry.builtIn()
        .capability<PresenceCapability>(team.cli);
    return MemberAvailabilityResolver.isReadyForAutomationInput(
      shell: shell,
      member: member,
      team: team,
      teamMode: team.teamMode,
      globalPresets: globalPresets,
      bus: tab.teamBus,
      claudeRosterWorking: false,
      usesClaudeRoster: presenceCap?.usesClaudeRoster ?? false,
      usesShellActivity: presenceCap?.usesShellActivity ?? false,
    );
  }

  @override
  Future<void> materializeMember(
    String sessionId,
    String memberId,
    String bootstrap,
  ) async {
    final tab = _tabStore.bySessionId(sessionId);
    if (tab == null) return;

    final session = tab.persistedSession;
    final isPersonal = session == null || session.sessionTeam.trim().isEmpty;

    if (isPersonal) {
      final ready = Completer<void>();
      _memberReady[(sessionId, memberId)] = ready;
      final shell = tab.memberShells[memberId];
      if (shell != null && shell.isRunning) {
        markMemberReady(sessionId, memberId);
      }
      await ready.future;
      return;
    }

    final team = _activeTeam();
    if (team == null) return;
    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => const TeamMemberConfig(id: '', name: ''),
    );
    if (!member.isValid) return;
    final ready = Completer<void>();
    _memberReady[(sessionId, memberId)] = ready;
    final shell = tab.memberShells[memberId];
    if (shell != null && shell.isRunning) {
      if (shell.isConnected) {
        appLogger.d(
          '[team-bus] materialize already-connected member=$memberId '
          'session=$sessionId',
        );
      }
      markMemberReady(sessionId, memberId);
    } else {
      appLogger.d(
        '[team-bus] materialize await-connect member=$memberId '
        'session=$sessionId '
        'isRunning=${shell?.isRunning ?? false} '
        'isConnecting=${shell?.isConnecting ?? false}',
      );
      _connector.scheduleMemberConnect(team, member, tab);
    }
    await ready.future;
  }

  @override
  void injectMemberStdin(String sessionId, String memberId, String text) {
    unawaited(
      _deliverMemberStdin(
        sessionId,
        memberId,
        text,
        automation: true,
        latchUserTurn: false,
      ),
    );
  }

  /// Bracketed-paste + CR for full-screen CLIs; [automation] uses grid ACK.
  Future<void> _deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) async {
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[team-bus] pty-inject skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _beginMemberTurnForPtyDelivery(
      sessionId,
      memberId,
      shell,
      latchUserTurn: latchUserTurn,
    );
    final usesFullScreen = _memberUsesFullScreen(sessionId, memberId);
    appLogger.d(
      '[team-bus] pty-inject member=$memberId '
      'session=$sessionId fullscreen=$usesFullScreen '
      'automation=$automation '
      'chars=${trimmed.length} '
      'preview=${_doorbellLogPreview(trimmed)}',
    );
    if (usesFullScreen) {
      final gridAck = _memberUsesGridPasteAck(sessionId, memberId);
      final settle = _pasteSettleForMember(
        sessionId,
        memberId,
        automation: automation && gridAck,
      );
      if (automation && gridAck) {
        await _ptyInject.deliver(
          shell: shell,
          sessionId: sessionId,
          memberId: memberId,
          text: trimmed,
          pasteSettle: settle,
          aborted: () => _ptyAckAborted(shell),
          crAckConfig: _crAckForMember(sessionId, memberId),
        );
      } else {
        await shell.submitFullScreenInput(trimmed, pasteSettleDelay: settle);
      }
    } else {
      shell.writeln(trimmed);
    }
  }

  bool _ptyAckAborted(TerminalSession shell) =>
      _isClosed() || !shell.isConnected;

  CliTool _memberCli(String sessionId, String memberId) {
    final tab = _tabStore.bySessionId(sessionId);
    return SessionMemberCliResolver.resolve(
      persistedSession: tab?.persistedSession,
      team: _activeTeam(),
      memberId: memberId,
      cliForMember: _shellFactory.cliForMember,
      globalPresets: _globalPresets(),
    );
  }

  bool _memberUsesFullScreen(String sessionId, String memberId) {
    final cli = _memberCli(sessionId, memberId);
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    return behavior?.usesFullScreenInput ?? false;
  }

  bool _memberUsesGridPasteAck(String sessionId, String memberId) {
    final cli = _memberCli(sessionId, memberId);
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    return behavior?.usesGridPasteAck ?? true;
  }

  Duration _pasteSettleForMember(
    String sessionId,
    String memberId, {
    required bool automation,
  }) {
    final cli = _memberCli(sessionId, memberId);
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    final base =
        behavior?.fullScreenPasteSettleDelay ??
        TerminalSession.fullScreenSubmitDelay;
    if (!automation) return base;
    return Duration(
      milliseconds: base.inMilliseconds < 500 ? 500 : base.inMilliseconds,
    );
  }

  FullscreenCrAckConfig _crAckForMember(String sessionId, String memberId) {
    final cli = _memberCli(sessionId, memberId);
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    return FullscreenCrAckConfig(
      strategy:
          behavior?.fullscreenCrAckStrategy ??
          FullscreenCrAckStrategy.anchorCellClears,
      composerPrefix: behavior?.fullscreenComposerPrefix,
    );
  }

  static String _doorbellLogPreview(String text) {
    final oneLine = text.replaceAll('\n', ' ').trim();
    if (oneLine.length <= 72) return oneLine;
    return '${oneLine.substring(0, 72)}…';
  }

  @override
  void retryDelivery(String sessionId, String memberId, String notice) {
    unawaited(_retryMemberDelivery(sessionId, memberId, notice));
  }

  Future<void> _retryMemberDelivery(
    String sessionId,
    String memberId,
    String notice,
  ) async {
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[team-bus] retry-delivery skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    if (_ptyAckAborted(shell)) return;
    if (_shouldSkipAutomationRetry(sessionId, memberId)) {
      _dropStaleAutomationRetry(sessionId, memberId, shell);
      return;
    }
    final trimmed = notice.trim();
    if (trimmed.isEmpty) return;
    _beginMemberTurnForPtyDelivery(
      sessionId,
      memberId,
      shell,
      latchUserTurn: false,
    );
    appLogger.d(
      '[team-bus] retry-delivery member=$memberId session=$sessionId '
      'preview=${_doorbellLogPreview(trimmed)}',
    );
    if (!_memberUsesGridPasteAck(sessionId, memberId)) {
      final settle = _pasteSettleForMember(
        sessionId,
        memberId,
        automation: false,
      );
      await shell.submitFullScreenInput(trimmed, pasteSettleDelay: settle);
      return;
    }
    final settle = _pasteSettleForMember(
      sessionId,
      memberId,
      automation: true,
    );
    await _ptyInject.retry(
      shell: shell,
      sessionId: sessionId,
      memberId: memberId,
      text: trimmed,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(shell),
      crAckConfig: _crAckForMember(sessionId, memberId),
    );
  }

  /// Operator paste (compose / automation / directToPty) latches
  /// [TerminalSession.userTurnActive]. Doorbell stdin inject does not — parked
  /// workers consume mail via MCP `wait_for_message`.
  void _beginMemberTurnForPtyDelivery(
    String sessionId,
    String memberId,
    TerminalSession shell, {
    bool latchUserTurn = true,
  }) {
    final bus = busForSession(sessionId);
    if (!latchUserTurn && (bus?.isWaitingForMessage(memberId) ?? false)) {
      return;
    }
    shell.markUserTurnStarted();
    bus?.markTurnStarted(memberId);
  }

  bool _shouldSkipAutomationRetry(String sessionId, String memberId) {
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    return PtyAutomationDeliveryGuard.shouldSkipRetry(
      bus: busForSession(sessionId),
      memberId: memberId,
      operatorTurnActive: shell?.userTurnActive ?? false,
      pendingAutomationRetry: _ptyInject.hasPendingRetry(sessionId, memberId),
    );
  }

  void _dropStaleAutomationRetry(
    String sessionId,
    String memberId,
    TerminalSession shell,
  ) {
    _ptyInject.clearPending(sessionId, memberId);
    shell.markUserTurnIdle();
    appLogger.d(
      '[team-bus] automation-retry-skipped member=$memberId '
      'session=$sessionId',
    );
  }

  Future<void> _retryAutomationTick(PtyAutomationRetryTick tick) async {
    final shell =
        _tabStore.bySessionId(tick.sessionId)?.memberShells[tick.memberId];
    if (shell == null) return;
    if (_ptyAckAborted(shell)) return;
    if (_shouldSkipAutomationRetry(tick.sessionId, tick.memberId)) {
      _dropStaleAutomationRetry(tick.sessionId, tick.memberId, shell);
      return;
    }
    _beginMemberTurnForPtyDelivery(tick.sessionId, tick.memberId, shell);
    final settle = _pasteSettleForMember(
      tick.sessionId,
      tick.memberId,
      automation: true,
    );
    if (!_memberUsesGridPasteAck(tick.sessionId, tick.memberId)) {
      await shell.submitFullScreenInput(tick.text, pasteSettleDelay: settle);
      return;
    }
    await _ptyInject.retry(
      shell: shell,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
      text: tick.text,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(shell),
      crAckConfig: _crAckForMember(tick.sessionId, tick.memberId),
    );
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

  TeamBus? busForSession(String sessionId) =>
      _tabStore.bySessionId(sessionId)?.teamBus;

  /// Delivers operator text to a member.
  ///
  /// Default: TeamBus mailbox when a bus is installed. [directToPty] injects at
  /// the member prompt (compose landing, automation, first prompt).
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) async {
    if (!directToPty) {
      final bus = busForSession(sessionId);
      if (bus != null) {
        bus.deliverUserCommand(memberId, message);
        return;
      }
    }
    await _deliverMemberStdin(
      sessionId,
      memberId,
      message,
      automation: true,
    );
  }

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

  /// Test seam: synchronously run one idle-watch tick (exposed through
  /// `ChatCubit.debugTickIdleWatch`).
  void debugTickIdleWatch() => _tickIdleWatch();

  void _tickIdleWatch() {
    if (_isClosed()) return;
    _ptyInject.tickRetries(
      shouldSkip: (tick) {
        if (!_shouldSkipAutomationRetry(tick.sessionId, tick.memberId)) {
          return false;
        }
        final shell =
            _tabStore.bySessionId(tick.sessionId)?.memberShells[tick.memberId];
        if (shell != null) {
          _dropStaleAutomationRetry(tick.sessionId, tick.memberId, shell);
        } else {
          _ptyInject.clearPending(tick.sessionId, tick.memberId);
        }
        return true;
      },
      onTick: (tick) {
        unawaited(_retryAutomationTick(tick));
      },
    );
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
        final parked = bus?.isWaitingForMessage(memberId) ?? false;
        final sessionId = tab.info.id;
        final inTurn = shell.userTurnActive ||
            _ptyInject.hasPendingRetry(sessionId, memberId) ||
            _ptyInject.isBusy(sessionId, memberId) ||
            (!parked && (bus?.isMemberInTurn(memberId) ?? false));
        final stillWorking = MemberTurnIdleSync.tick(
          turnKey: key,
          inTurn: inTurn,
          shell: shell,
          wasInTurn: _wasInTurn,
          endTurn: () {
            appLogger.d(
              '[idle-watch] end-turn member=$memberId '
              'session=${tab.info.id} '
              'busInTurn=${bus?.isMemberInTurn(memberId)}',
            );
            if (bus != null) {
              bus.onMemberIdle(memberId, fromPtyQuietWatch: true);
            }
            shell.markUserTurnIdle();
          },
        );
        if (stillWorking) tabWorking = true;
      });
      if (bus != null) {
        if (bus.anyMemberInTurn || tabWorking) working.add(tab.info.id);
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
