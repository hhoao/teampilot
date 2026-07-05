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
import '../../services/terminal/pty_inject_ack_retry.dart';
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

  /// Members currently running a PTY inject ACK loop (automation or nudge).
  /// Prevents the 1s watchdog from stacking a second loop while one is active.
  final Set<String> _ptyAckInProgress = {};

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
    // Doorbell notices are automation — they need the ACK loop just as much
    // as operator direct-to-PTY injections. The bus fires this at teammates
    // on mail/task arrival; if the first CR is swallowed by a not-yet-ready
    // Ink input box, the message is lost without the loop.
    unawaited(
      _submitMemberStdin(sessionId, memberId, text, automationDelivery: true),
    );
  }

  /// Bracketed-paste + CR for full-screen CLIs; [automationDelivery] uses a
  /// longer settle and awaits a follow-up CR (first Enter often becomes a
  /// literal newline right after boot).
  Future<void> _submitMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    bool automationDelivery = false,
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
    _beginMemberTurnForPtyDelivery(sessionId, memberId, shell);
    final team = _activeTeam();
    final cli = team == null
        ? CliTool.claude
        : _shellFactory.cliForMember(
            team,
            memberId,
            globalPresets: _globalPresets(),
          );
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(cli);
    final usesFullScreen = behavior?.usesFullScreenInput ?? false;
    appLogger.d(
      '[team-bus] pty-inject member=$memberId '
      'session=$sessionId fullscreen=$usesFullScreen '
      'automation=$automationDelivery '
      'chars=${trimmed.length} '
      'preview=${_doorbellLogPreview(trimmed)}',
    );
    if (usesFullScreen) {
      final base =
          behavior?.fullScreenPasteSettleDelay ??
          TerminalSession.fullScreenSubmitDelay;
      final settle = automationDelivery
          ? Duration(
              milliseconds: base.inMilliseconds < 500
                  ? 500
                  : base.inMilliseconds,
            )
          : base;
      if (automationDelivery) {
        // Paste → verify → CR → verify. Do not call [submitFullScreenInput]
        // first — a successful submit clears the input box and the old ACK loop
        // misread that as "paste never landed", reinjecting duplicates.
        await _ensureAutomationDelivered(
          shell,
          memberId,
          sessionId,
          trimmed,
          settle,
        );
      } else {
        await shell.submitFullScreenInput(trimmed, pasteSettleDelay: settle);
      }
    } else {
      shell.writeln(trimmed);
    }
  }

  /// Content-based ACK for doorbell / landing / automation PTY inject.
  ///
  /// 1. Clear staged input → bracketed paste only.
  /// 2. Locate [needle] on the visible grid (row/col anchor).
  /// 3. Standalone CR → re-check the **same anchor** (not global screen search).
  Future<void> _ensureAutomationDelivered(
    TerminalSession shell,
    String memberId,
    String sessionId,
    String text,
    Duration settle,
  ) async {
    if (_ptyAckInProgress.contains(memberId)) {
      appLogger.d(
        '[team-bus] submit-ack skipped ack-in-progress '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    _ptyAckInProgress.add(memberId);
    try {
      final needle = _screenNeedle(text);
      final maxReinject = PtyInjectAckTiming.reinjectMaxAttempts;
      appLogger.d(
        '[team-bus] submit-ack-start member=$memberId session=$sessionId '
        'needle="${_doorbellLogPreview(needle)}" '
        'pasteSettleMs=${settle.inMilliseconds} '
        'afterClearMs=${PtyInjectAckTiming.afterClear.inMilliseconds} '
        'afterPasteMs=${PtyInjectAckTiming.afterPaste.inMilliseconds} '
        'afterCrMs=${PtyInjectAckTiming.afterCr.inMilliseconds} '
        'afterReinjectMs=${PtyInjectAckTiming.afterReinject.inMilliseconds} '
        'crMax=${PtyInjectAckTiming.crMaxAttempts} '
        'reinjectMax=$maxReinject',
      );

      for (var reinject = 0; reinject <= maxReinject; reinject++) {
        if (_ptyAckAborted(shell)) {
          appLogger.w(
            '[team-bus] submit-ack-aborted member=$memberId session=$sessionId '
            'reinject=$reinject/$maxReinject (closed/disconnected)',
          );
          return;
        }

        if (reinject > 0) {
          await Future<void>.delayed(PtyInjectAckTiming.afterReinject);
        }

        await shell.syncDisplayGrid();
        var anchor = shell.locateFullscreenPromptNeedle(
          needle,
          scanRows: 24,
        );
        if (anchor != null) {
          appLogger.d(
            '[team-bus] submit-paste-already-visible member=$memberId '
            'session=$sessionId reinject=$reinject/$maxReinject '
            'anchor=$anchor — skip clear→paste',
          );
        } else {
          appLogger.d(
            '[team-bus] submit-ack-round member=$memberId session=$sessionId '
            'reinject=$reinject/$maxReinject phase=clear→paste',
          );
          await shell.clearStagedInput();
          await Future<void>.delayed(PtyInjectAckTiming.afterClear);
          await shell.pasteText(text);
          await Future<void>.delayed(settle);
          await Future<void>.delayed(PtyInjectAckTiming.afterPaste);

          appLogger.d(
            '[team-bus] submit-ack-scan member=$memberId session=$sessionId '
            'reinject=$reinject/$maxReinject phase=locate-anchor',
          );
          await shell.syncDisplayGrid();
          anchor = shell.locateFullscreenPromptNeedle(needle, scanRows: 24);
        }
        if (anchor == null) {
          appLogger.w(
            '[team-bus] submit-paste-not-found member=$memberId '
            'session=$sessionId reinject=$reinject/$maxReinject '
            'needle="${_doorbellLogPreview(needle)}" '
            'probeWindow:\n${shell.describeProbeWindow()}',
          );
          if (reinject < maxReinject) {
            appLogger.d(
              '[team-bus] submit-paste-retry member=$memberId session=$sessionId '
              'reinject=$reinject/$maxReinject '
              'afterReinjectMs=${PtyInjectAckTiming.afterReinject.inMilliseconds}',
            );
            continue;
          }
          appLogger.w(
            '[team-bus] submit-ack-failed member=$memberId session=$sessionId '
            '— paste never landed after $maxReinject reinjects',
          );
          return;
        }
        final pasteAnchor = anchor;
        appLogger.d(
          '[team-bus] submit-paste-found member=$memberId session=$sessionId '
          'reinject=$reinject/$maxReinject anchor=$pasteAnchor',
        );

        appLogger.d(
          '[team-bus] submit-cr-first member=$memberId session=$sessionId '
          'reinject=$reinject anchor=$pasteAnchor',
        );
        await shell.submitPendingCr();

        final crOutcome = await ptyAckPollRetry(
          settle: PtyInjectAckTiming.afterCr,
          maxAttempts: PtyInjectAckTiming.crMaxAttempts,
          aborted: () => _ptyAckAborted(shell),
          isAcked: (_) async {
            await shell.syncDisplayGrid();
            return !shell.isFullscreenPromptAtAnchor(pasteAnchor);
          },
          onRetry: (ctx) async {
            appLogger.d(
              '[team-bus] submit-cr-retry member=$memberId session=$sessionId '
              'reinject=$reinject crAttempt=${ctx.attempt + 1}/${ctx.maxAttempts}',
            );
            await shell.submitPendingCr();
          },
          onStillPending: (ctx) {
            appLogger.w(
              '[team-bus] submit-cr-swallowed member=$memberId '
              'session=$sessionId reinject=$reinject '
              'crAttempt=${ctx.attempt}/${ctx.maxAttempts} '
              'anchor=$pasteAnchor — prompt still at anchor',
            );
          },
          onAcked: (ctx) {
            appLogger.d(
              '[team-bus] submit-ack member=$memberId session=$sessionId '
              'reinject=$reinject crAttempt=${ctx.attempt}/${ctx.maxAttempts} '
              '— prompt cleared at anchor (CR succeeded)',
            );
          },
        );
        switch (crOutcome) {
          case PtyAckPollOutcome.acked:
            return;
          case PtyAckPollOutcome.aborted:
            appLogger.w(
              '[team-bus] submit-ack-aborted member=$memberId session=$sessionId '
              'reinject=$reinject phase=cr-poll',
            );
            return;
          case PtyAckPollOutcome.exhausted:
            appLogger.w(
              '[team-bus] submit-cr-exhausted member=$memberId session=$sessionId '
              'reinject=$reinject/$maxReinject — will clear and repaste',
            );
        }
      }
      appLogger.w(
        '[team-bus] submit-ack-failed member=$memberId session=$sessionId '
        '— text stuck in input box after $maxReinject reinjects',
      );
    } finally {
      _ptyAckInProgress.remove(memberId);
    }
  }

  bool _ptyAckAborted(TerminalSession shell) =>
      _isClosed() || !shell.isConnected;

  /// All PTY message delivery (doorbell, landing directToPty, automation) must
  /// mark in-turn the same way as a user line at the member prompt.
  void _beginMemberTurnForPtyDelivery(
    String sessionId,
    String memberId,
    TerminalSession shell,
  ) {
    final bus = busForSession(sessionId);
    if (bus != null) {
      shell.activityTracker.latchTurnQuietBaseline();
      bus.markTurnStarted(memberId);
      return;
    }
    shell.markUserTurnStarted();
  }

  /// Distinctive substring for grid anchor search after paste.
  ///
  /// Doorbell lines carry a stable `[teammate-bus]` prefix; short landing text
  /// (e.g. CJK) fits whole. Long free-form text falls back to the tail ~40
  /// chars where the cursor usually sits.
  static String _screenNeedle(String text) {
    final trimmed = text.trim();
    const busTag = '[teammate-bus]';
    if (trimmed.startsWith(busTag)) {
      return trimmed.length <= 40 ? trimmed : trimmed.substring(0, 40);
    }
    if (trimmed.length <= 40) return trimmed;
    return trimmed.substring(trimmed.length - 40);
  }

  static String _doorbellLogPreview(String text) {
    final oneLine = text.replaceAll('\n', ' ').trim();
    if (oneLine.length <= 72) return oneLine;
    return '${oneLine.substring(0, 72)}…';
  }

  @override
  void submitMemberPending(String sessionId, String memberId) {
    // 门铃重试：只补回车，提交已卡在框里的上一条提示，绝不重打全文（见
    // [MemberLauncher.nudgeSubmit]）。CR-only 在全屏 / 普通 CLI 都安全（空 prompt
    // 上回车是 no-op）。
    final shell = _tabStore.bySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[team-bus] pty-nudge-cr skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    // Don't stack a second ACK loop if one is already polling for this member
    // — the 1s watchdog tick can fire before the previous loop's ACK window
    // expires. The in-flight loop will retry the CR itself if needed.
    if (_ptyAckInProgress.contains(memberId)) {
      appLogger.d(
        '[team-bus] pty-nudge-cr skipped ack-in-progress '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    appLogger.d('[team-bus] pty-nudge-cr member=$memberId session=$sessionId');
    unawaited(_nudgeAndAck(shell, memberId, sessionId));
  }

  /// Nudge CR loop for the doorbell watchdog path. Sends one CR at a time and
  /// checks whether the input row cleared — avoids burst CRs that stack submits.
  Future<void> _nudgeAndAck(
    TerminalSession shell,
    String memberId,
    String sessionId,
  ) async {
    _ptyAckInProgress.add(memberId);
    try {
      final maxRounds = PtyInjectAckTiming.nudgeMaxAttempts;
      appLogger.d(
        '[team-bus] nudge-ack-start member=$memberId session=$sessionId '
        'afterCrMs=${PtyInjectAckTiming.afterCr.inMilliseconds} '
        'roundMax=$maxRounds',
      );

      for (var round = 0; round <= maxRounds; round++) {
        if (_ptyAckAborted(shell)) {
          appLogger.w(
            '[team-bus] nudge-ack-aborted member=$memberId session=$sessionId '
            'round=$round/$maxRounds (closed/disconnected)',
          );
          return;
        }
        await shell.syncDisplayGrid();
        final anchor = shell.captureBottomInputAnchor();
        if (anchor == null) {
          appLogger.d(
            '[team-bus] nudge-ack-done member=$memberId session=$sessionId '
            'round=$round/$maxRounds — no staged input anchor',
          );
          return;
        }
        appLogger.d(
          '[team-bus] nudge-ack-round member=$memberId session=$sessionId '
          'round=$round/$maxRounds anchor=$anchor',
        );

        await shell.submitPendingCr();

        final outcome = await ptyAckPollRetry(
          settle: PtyInjectAckTiming.afterCr,
          maxAttempts: 0,
          aborted: () => _ptyAckAborted(shell),
          isAcked: (_) async {
            await shell.syncDisplayGrid();
            return !shell.isFullscreenPromptAtAnchor(anchor);
          },
          onRetry: (_) async {},
          onStillPending: (ctx) {
            appLogger.w(
              '[team-bus] nudge-ack-still-stuck member=$memberId '
              'session=$sessionId round=$round/$maxRounds '
              'anchor=$anchor attempt=${ctx.attempt}/${ctx.maxAttempts}',
            );
          },
          onAcked: (ctx) {
            appLogger.d(
              '[team-bus] nudge-ack-done member=$memberId session=$sessionId '
              'round=$round/$maxRounds attempt=${ctx.attempt}/${ctx.maxAttempts} '
              '— prompt cleared at anchor',
            );
          },
        );
        switch (outcome) {
          case PtyAckPollOutcome.acked:
            return;
          case PtyAckPollOutcome.aborted:
            appLogger.w(
              '[team-bus] nudge-ack-aborted member=$memberId session=$sessionId '
              'round=$round phase=cr-poll',
            );
            return;
          case PtyAckPollOutcome.exhausted:
            appLogger.w(
              '[team-bus] nudge-ack-retry member=$memberId session=$sessionId '
              'round=$round/$maxRounds — will retry next round',
            );
        }
      }
      appLogger.w(
        '[team-bus] nudge-ack-failed member=$memberId session=$sessionId '
        '— input box still has content after $maxRounds rounds; '
        'watchdog will retry',
      );
    } finally {
      _ptyAckInProgress.remove(memberId);
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
  /// Default: TeamBus mailbox when a bus is installed. [directToPty] skips the
  /// bus and injects into the member PTY (compose landing / first prompt).
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
    await _submitMemberStdin(
      sessionId,
      memberId,
      message,
      automationDelivery: true,
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
            appLogger.d(
              '[idle-watch] end-turn member=$memberId '
              'session=${tab.info.id} '
              'busInTurn=${bus?.isMemberInTurn(memberId)}',
            );
            if (bus != null) {
              bus.onMemberIdle(memberId, fromPtyQuietWatch: true);
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
