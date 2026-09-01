import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/agent_runtime/runtime_event.dart';
import '../../services/team_bus/mailbox_delivery.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/terminal/fullscreen_cr_ack_config.dart';
import '../../services/terminal/fullscreen_input_readiness.dart';
import '../../services/terminal/fullscreen_pty_automation.dart';
import '../../services/terminal/member_pty_inject_service.dart';
import '../../services/prompt_delivery/prompt_delivery.dart';
import '../../services/prompt_delivery/prompt_delivery_coordinator.dart';
import '../../services/prompt_delivery/prompt_delivery_store.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/terminal/terminal_input_command_queue.dart';
import '../../services/terminal/terminal_fullscreen_pty_port.dart';
import '../../services/terminal/terminal_session.dart';
import '../../utils/logging/logger.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'tab_member_coordination_factory.dart';

/// Full-screen PTY inject, automation retry, and mailbox doorbell delivery.
final class TabMemberPtyDelivery {
  TabMemberPtyDelivery({
    required ChatTabStore tabStore,
    required ChatSessionShellFactory shellFactory,
    required List<CliPreset> Function() globalPresets,
    required TeamProfile? Function() activeTeam,
    required bool Function() isClosed,
    required TabMemberCoordinationFactory coordinationFactory,
    void Function(String sessionId, String memberId)? onAfterTurnLatched,
    void Function(String sessionId)? onUserActivity,
    MemberPtyInjectService? ptyInject,
    PromptDeliveryCoordinator? promptDeliveries,
  }) : _tabStore = tabStore,
       _shellFactory = shellFactory,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _isClosed = isClosed,
       _coordinationFactory = coordinationFactory,
       _onAfterTurnLatched = onAfterTurnLatched,
       _onUserActivity = onUserActivity,
       _promptDeliveries = promptDeliveries ?? _tabPromptDeliveries(tabStore) {
    _ptyInject = ptyInject ?? MemberPtyInjectService();
  }

  final ChatTabStore _tabStore;
  final ChatSessionShellFactory _shellFactory;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final bool Function() _isClosed;
  final TabMemberCoordinationFactory _coordinationFactory;
  final void Function(String sessionId, String memberId)? _onAfterTurnLatched;
  final void Function(String sessionId)? _onUserActivity;
  late final MemberPtyInjectService _ptyInject;
  final PromptDeliveryCoordinator _promptDeliveries;
  final Map<String, DateTime> _lastBootGateNudge = {};
  final Map<String, FullscreenInputSurfaceWatch> _surfaceWatches = {};
  final Map<String, String> _directDeliveryBySeat = {};
  final Map<String, int> _directEpochBySeat = {};
  final Set<String> _directTurnLatched = {};

  TeamBus? busForSession(String sessionId) =>
      _tabStore.openTabBySessionId(sessionId)?.teamBus;

  static const _composerProbeRows = 52;
  static const _bootGateNudgeGap = Duration(milliseconds: 600);

  TerminalBehaviorCapability? _behaviorFor(String sessionId, String memberId) {
    return CliToolRegistry.builtIn().capability<TerminalBehaviorCapability>(
      _memberCli(sessionId, memberId),
    );
  }

  Future<void> syncMemberInputSurface(String sessionId, String memberId) async {
    final shell = _tabStore
        .openTabBySessionId(sessionId)
        ?.memberShells[memberId];
    if (shell == null) return;
    await shell.probe.syncDisplayGrid();
  }

  bool isMemberComposerSurfaceReady(String sessionId, String memberId) {
    final shell = _tabStore
        .openTabBySessionId(sessionId)
        ?.memberShells[memberId];
    if (shell == null || !shell.activityTracker.isBootFrameReady) {
      return false;
    }
    final window = shell.probe.describeProbeWindow(
      scanRows: _composerProbeRows,
    );
    final key = '$sessionId:$memberId';
    final watch = _surfaceWatches.putIfAbsent(
      key,
      () => FullscreenInputSurfaceWatch(),
    );
    return watch.observe(
      readiness: _behaviorFor(sessionId, memberId)?.inputReadiness,
      probeWindow: window,
    );
  }

  void maybeNudgeMemberBootGate(String sessionId, String memberId) {
    final shell = _tabStore
        .openTabBySessionId(sessionId)
        ?.memberShells[memberId];
    if (shell == null) return;
    final readiness = _behaviorFor(sessionId, memberId)?.inputReadiness;
    if (readiness == null || !readiness.waitsForSurface) return;
    final window = shell.probe.describeProbeWindow(
      scanRows: _composerProbeRows,
    );
    if (readiness.isReady(window)) return;
    if (!readiness.needsBootGateNudge(window)) return;
    final key = '$sessionId:$memberId';
    final now = DateTime.now();
    final last = _lastBootGateNudge[key];
    if (last != null && now.difference(last) < _bootGateNudgeGap) return;
    _lastBootGateNudge[key] = now;
    appLogger.d(
      '[session-runtime] boot-gate nudge member=$memberId session=$sessionId',
    );
    shell.input.writeToPty('\r');
  }

  void abortMemberInject(String sessionId, String memberId) {
    final key = _seatKey(sessionId, memberId);
    _directEpochBySeat.update(key, (value) => value + 1, ifAbsent: () => 1);
    final directDelivery = _directDeliveryBySeat.remove(key);
    if (directDelivery != null) {
      _promptDeliveries.invalidateSubmittedDelivery(directDelivery);
    }
    _ptyInject.requestAbort(sessionId, memberId);
    if (!_ptyInject.isDelivering(sessionId, memberId)) {
      _ptyInject.clearAbort(sessionId, memberId);
    }
  }

  /// Bracketed-paste + CR for full-screen CLIs; [automation] uses grid ACK.
  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) async {
    final shell = _tabStore
        .openTabBySessionId(sessionId)
        ?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[session-runtime] pty-inject skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final isMailDoorbell = !latchUserTurn && _isMailDoorbellText(trimmed);

    final isOperatorTurn = latchUserTurn;
    final usesFullScreen = _memberUsesFullScreen(sessionId, memberId);
    appLogger.d(
      '[session-runtime] pty-inject member=$memberId '
      'session=$sessionId fullscreen=$usesFullScreen '
      'automation=$automation '
      'chars=${trimmed.length} '
      'preview=${_doorbellLogPreview(trimmed)}',
    );
    if (usesFullScreen) {
      if (isMailDoorbell) {
        await shell.probe.syncDisplayGrid();
        // Defer before Started: a missed paste must not burn attempts or
        // leave inFlight while the composer is still booting.
        if (_deferMailDoorbellIfBooting(sessionId, memberId, shell, trimmed)) {
          return;
        }
        if (!_beginMailDelivery(sessionId, memberId)) return;
      }
      await _deliverFullScreen(
        sessionId: sessionId,
        memberId: memberId,
        shell: shell,
        text: trimmed,
        automation: automation,
        isMailDoorbell: isMailDoorbell,
        isOperatorTurn: isOperatorTurn,
      );
      return;
    }
    shell.input.writeln(trimmed);
    if (isOperatorTurn) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
  }

  Future<void> retryMemberDelivery(
    String sessionId,
    String memberId,
    String notice,
  ) async {
    final shell = _tabStore
        .openTabBySessionId(sessionId)
        ?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[session-runtime] retry-delivery skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    if (_ptyAckAborted(shell, sessionId: sessionId, memberId: memberId)) return;
    final trimmed = notice.trim();
    if (trimmed.isEmpty) return;
    final isMailDoorbell = _isMailDoorbellText(trimmed);
    if (isMailDoorbell) {
      await shell.probe.syncDisplayGrid();
      if (_deferMailDoorbellIfBooting(sessionId, memberId, shell, trimmed)) {
        return;
      }
      if (!_beginMailDelivery(sessionId, memberId)) return;
    }
    appLogger.d(
      '[session-runtime] retry-delivery member=$memberId session=$sessionId '
      'preview=${_doorbellLogPreview(trimmed)}',
    );
    if (!_memberUsesGridPasteAck(sessionId, memberId)) {
      final settle = _pasteSettleForMember(
        sessionId,
        memberId,
        automation: false,
      );
      await shell.input.submitFullScreenInput(
        trimmed,
        pasteSettleDelay: settle,
      );
      if (isMailDoorbell) {
        _reportMailDeliveryOutcome(
          sessionId,
          memberId,
          FullscreenPtyDeliveryOutcome.submitted,
        );
      }
      return;
    }
    final settle = _pasteSettleForMember(sessionId, memberId, automation: true);
    final outcome = await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: sessionId,
      memberId: memberId,
      text: trimmed,
      pasteSettle: settle,
      aborted: () =>
          _ptyAckAborted(shell, sessionId: sessionId, memberId: memberId),
      crAckConfig: _crAckForMember(sessionId, memberId),
      painted: shell.observationPainted,
    );
    if (isMailDoorbell) {
      _reportMailDeliveryOutcome(sessionId, memberId, outcome);
    }
  }

  /// Default: TeamBus mailbox when a bus is installed. [directToPty] injects at
  /// the member prompt (compose landing, automation, first prompt).
  ///
  /// Returns the mailbox message id when routed via TeamBus, or the durable
  /// prompt-delivery id when [directToPty] is true and the terminal adapter
  /// confirms submission. Returns `null` when the direct delivery is dropped,
  /// unconfirmed, or interrupted before it could be issued.
  /// When [directToPty] is false and no bus is installed, returns `null`
  /// without falling back to PTY inject (caller must not treat that as success).
  Future<String?> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
    String? deliveryId,
  }) async {
    if (message.trim().isEmpty) return null;
    _onUserActivity?.call(sessionId);
    if (!directToPty) {
      final bus = busForSession(sessionId);
      if (bus == null) return null;
      final id = bus.deliverUserCommand(memberId, message);
      return id.isEmpty ? null : id;
    }
    final key = _seatKey(sessionId, memberId);
    final epoch = (_directEpochBySeat[key] ?? 0) + 1;
    _directEpochBySeat[key] = epoch;
    final delivery = await _promptDeliveries.submit(
      PromptDeliveryRequest(
        seat: RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
        cli: _memberCli(sessionId, memberId),
        text: message,
        deliveryId: deliveryId,
      ),
    );
    if (_directEpochBySeat[key] != epoch) {
      await _promptDeliveries.failBeforeSubmit(delivery.id);
      return null;
    }
    _directDeliveryBySeat[key] = delivery.id;
    final result = await _promptDeliveries.issueSubmit(delivery.id);
    if (_directDeliveryBySeat[key] == delivery.id &&
        result == PromptSubmissionResult.submitted &&
        _directTurnLatched.add(delivery.id)) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
    return result == PromptSubmissionResult.submitted ? delivery.id : null;
  }

  /// Delivers a direct prompt with a caller-owned idempotency id.
  Future<PromptDeliverySubmission> deliverTrackedUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    required String deliveryId,
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      return const PromptDeliverySubmission(
        deliveryId: '',
        submitted: false,
        state: 'failed',
      );
    }
    _onUserActivity?.call(sessionId);
    final key = _seatKey(sessionId, memberId);
    final delivery = await _promptDeliveries.submit(
      PromptDeliveryRequest(
        seat: RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
        cli: _memberCli(sessionId, memberId),
        text: message,
        deliveryId: deliveryId,
      ),
    );
    if (delivery.state == PromptDeliveryState.submitIssued ||
        delivery.state == PromptDeliveryState.confirmed) {
      return PromptDeliverySubmission(
        deliveryId: delivery.id,
        submitted: true,
        state: delivery.state.name,
      );
    }
    if (!delivery.state.canIssueSubmit) {
      return PromptDeliverySubmission(
        deliveryId: delivery.id,
        submitted: false,
        state: delivery.state.name,
      );
    }
    final epoch = (_directEpochBySeat[key] ?? 0) + 1;
    _directEpochBySeat[key] = epoch;
    if (_directEpochBySeat[key] != epoch) {
      await _promptDeliveries.failBeforeSubmit(delivery.id);
      return PromptDeliverySubmission(
        deliveryId: delivery.id,
        submitted: false,
        state: 'failed',
      );
    }
    _directDeliveryBySeat[key] = delivery.id;
    final result = await _promptDeliveries.issueSubmit(delivery.id);
    if (_directDeliveryBySeat[key] == delivery.id &&
        result == PromptSubmissionResult.submitted &&
        _directTurnLatched.add(delivery.id)) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
    return PromptDeliverySubmission(
      deliveryId: delivery.id,
      submitted: result == PromptSubmissionResult.submitted,
      state: result == PromptSubmissionResult.submitted
          ? PromptDeliveryState.submitIssued.name
          : result == PromptSubmissionResult.dropped
          ? PromptDeliveryState.submittedUnknown.name
          : PromptDeliveryState.failed.name,
    );
  }

  Future<void> _deliverFullScreen({
    required String sessionId,
    required String memberId,
    required TerminalSession shell,
    required String text,
    required bool automation,
    required bool isMailDoorbell,
    required bool isOperatorTurn,
  }) async {
    final gridAck = _memberUsesGridPasteAck(sessionId, memberId);
    final settle = _pasteSettleForMember(
      sessionId,
      memberId,
      automation: automation && gridAck,
    );
    if (automation && gridAck) {
      final outcome = await _ptyInject.deliver(
        input: shell.input,
        probe: shell.probe,
        sessionId: sessionId,
        memberId: memberId,
        text: text,
        pasteSettle: settle,
        aborted: () =>
            _ptyAckAborted(shell, sessionId: sessionId, memberId: memberId),
        crAckConfig: _crAckForMember(sessionId, memberId),
        painted: shell.observationPainted,
      );
      if (isMailDoorbell) {
        _reportMailDeliveryOutcome(sessionId, memberId, outcome);
      } else if (isOperatorTurn &&
          outcome == FullscreenPtyDeliveryOutcome.submitted) {
        _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
      }
      return;
    }
    await shell.input.submitFullScreenInput(text, pasteSettleDelay: settle);
    if (isMailDoorbell) {
      _reportMailDeliveryOutcome(
        sessionId,
        memberId,
        FullscreenPtyDeliveryOutcome.submitted,
      );
    } else if (isOperatorTurn) {
      _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
    }
  }

  bool _beginMailDelivery(String sessionId, String memberId) {
    final bus = busForSession(sessionId);
    bus?.noteMailDeliveryStarted(memberId);
    return bus?.memberById(memberId)?.deliveryPhase !=
        MailboxDeliveryPhase.failed;
  }

  bool _ptyAckAborted(
    TerminalSession shell, {
    String? sessionId,
    String? memberId,
  }) {
    if (_isClosed() || !shell.isConnected) return true;
    if (sessionId != null &&
        memberId != null &&
        _ptyInject.isAbortRequested(sessionId, memberId)) {
      return true;
    }
    return false;
  }

  CliTool _memberCli(String sessionId, String memberId) {
    final tab = _tabStore.openTabBySessionId(sessionId);
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
        TerminalInputController.fullScreenSubmitDelay;
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

  static bool _isMailDoorbellText(String text) =>
      text == TeamBus.doorbellNotice;

  static String _seatKey(String sessionId, String memberId) =>
      '$sessionId\u0000$memberId';

  /// 门铃投递的 boot 门控:全屏 TUI 未就绪时推迟到重试 tick,避免盲粘启动屏。
  /// 返回 true 表示已推迟(调用方应 return)。只对邮件门铃生效——operator 直投
  /// 已由 [ensureMemberInputReady] 等过 composer 表面。
  bool _deferMailDoorbellIfBooting(
    String sessionId,
    String memberId,
    TerminalSession shell,
    String text,
  ) {
    if (!_isMailDoorbellText(text)) return false;
    if (isMemberComposerSurfaceReady(sessionId, memberId)) return false;
    if (shell.activityTracker.isBootFrameReady) {
      maybeNudgeMemberBootGate(sessionId, memberId);
    }
    appLogger.d(
      '[session-runtime] doorbell deferred (surface) member=$memberId '
      'session=$sessionId boot=${shell.activityTracker.isBootFrameReady}',
    );
    return true;
  }

  void _reportMailDeliveryOutcome(
    String sessionId,
    String memberId,
    FullscreenPtyDeliveryOutcome outcome,
  ) {
    final bus = busForSession(sessionId);
    if (bus == null) return;
    switch (outcome) {
      case FullscreenPtyDeliveryOutcome.submitted:
        bus.noteMailDeliverySubmitted(memberId);
        _onAfterTurnLatched?.call(sessionId, memberId);
      case FullscreenPtyDeliveryOutcome.crStuck:
        bus.noteMailDeliveryAttemptFailed(
          memberId,
          error: MailboxDeliveryError.crStuck,
        );
      case FullscreenPtyDeliveryOutcome.pasteNotFound:
        bus.noteMailDeliveryAttemptFailed(
          memberId,
          error: MailboxDeliveryError.pasteNotFound,
        );
      case FullscreenPtyDeliveryOutcome.aborted:
        bus.noteMailDeliveryAborted(memberId);
    }
  }

  void _markMemberTurnStartedOnSubmitSuccess(
    String sessionId,
    String memberId,
  ) {
    _coordinationFactory.forMember(sessionId, memberId)?.latchTurnStarted();
    _onAfterTurnLatched?.call(sessionId, memberId);
  }
}

PromptDeliveryCoordinator _tabPromptDeliveries(ChatTabStore tabStore) =>
    PromptDeliveryCoordinator(
      store: MemoryPromptDeliveryStore(),
      commands: TabPromptDeliveryCommands(tabStore),
    );

/// Transitional terminal adapter until app-scoped lifecycle wiring supplies a
/// persistent coordinator. Its writes still flow through the fenced terminal
/// command queue and are controlled by the coordinator's delivery id.
final class TabPromptDeliveryCommands implements PromptDeliveryCommands {
  TabPromptDeliveryCommands(
    this._tabStore, {
    FullscreenPtyAutomation? automation,
  }) : _automation = automation ?? FullscreenPtyAutomation();

  final ChatTabStore _tabStore;
  final FullscreenPtyAutomation _automation;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    final shell = _tabStore
        .openTabBySessionId(delivery.seat.sessionId)
        ?.memberShells[delivery.seat.memberId];
    if (shell == null) return PromptSubmissionResult.failed;
    final behavior = CliToolRegistry.builtIn()
        .capability<TerminalBehaviorCapability>(delivery.cli);
    if (behavior?.usesFullScreenInput == true &&
        behavior?.usesGridPasteAck == true) {
      final outcome = await _automation.deliverPasteAndSubmit(
        port: TerminalFullscreenPtyPort(
          input: shell.input,
          probe: shell.probe,
          aborted: () => !shell.isConnected || !canExecute(),
          crAckConfig: FullscreenCrAckConfig(
            strategy:
                behavior?.fullscreenCrAckStrategy ??
                FullscreenCrAckStrategy.anchorCellClears,
            composerPrefix: behavior?.fullscreenComposerPrefix,
          ),
          painted: shell.observationPainted,
        ),
        text: delivery.text,
        pasteSettle:
            behavior?.fullScreenPasteSettleDelay ??
            TerminalInputController.fullScreenSubmitDelay,
      );
      switch (outcome) {
        case FullscreenPtyDeliveryOutcome.submitted:
          return PromptSubmissionResult.submitted;
        case FullscreenPtyDeliveryOutcome.aborted:
          return canExecute()
              ? PromptSubmissionResult.unconfirmed
              : PromptSubmissionResult.dropped;
        case FullscreenPtyDeliveryOutcome.pasteNotFound:
        case FullscreenPtyDeliveryOutcome.crStuck:
          return PromptSubmissionResult.unconfirmed;
      }
    }
    final result = await shell.input.submitFullScreenInput(
      delivery.text,
      canExecute: canExecute,
    );
    switch (result) {
      case TerminalInputCommandResult.written:
        return PromptSubmissionResult.submitted;
      case TerminalInputCommandResult.dropped:
        return PromptSubmissionResult.dropped;
    }
  }
}
