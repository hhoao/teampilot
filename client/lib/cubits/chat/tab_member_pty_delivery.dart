import 'package:flutter/foundation.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/team_bus/mailbox_delivery.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/terminal/fullscreen_cr_ack_config.dart';
import '../../services/terminal/fullscreen_input_readiness.dart';
import '../../services/terminal/fullscreen_pty_automation.dart';
import '../../services/terminal/member_pty_inject_service.dart';
import '../../services/terminal/prompt_submit_ack_tracker.dart';
import '../../services/terminal/pty_automation_delivery_guard.dart';
import '../../services/terminal/pty_automation_retry_queue.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
import '../../services/terminal/terminal_input_controller.dart';
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
    PromptSubmitAckTracker? promptAckTracker,
  }) : _tabStore = tabStore,
       _shellFactory = shellFactory,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _isClosed = isClosed,
       _coordinationFactory = coordinationFactory,
       _onAfterTurnLatched = onAfterTurnLatched,
       _onUserActivity = onUserActivity,
       _promptAckTracker = promptAckTracker ?? PromptSubmitAckTracker() {
    _ptyInject =
        ptyInject ??
        MemberPtyInjectService(
          onDeliveryRetryExhausted: _onDeliveryRetryExhausted,
          ackTracker: _promptAckTracker,
        );
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
  final PromptSubmitAckTracker _promptAckTracker;
  final Map<String, DateTime> _lastBootGateNudge = {};

  TeamBus? busForSession(String sessionId) =>
      _tabStore.openTabBySessionId(sessionId)?.teamBus;

  bool hasPendingRetry(String sessionId, String memberId) =>
      _ptyInject.hasPendingRetry(sessionId, memberId);

  static const _composerProbeRows = 52;
  static const _bootGateNudgeGap = Duration(milliseconds: 600);

  TerminalBehaviorCapability? _behaviorFor(String sessionId, String memberId) {
    return CliToolRegistry.builtIn().capability<TerminalBehaviorCapability>(
      _memberCli(sessionId, memberId),
    );
  }

  Future<void> syncMemberInputSurface(String sessionId, String memberId) async {
    final shell =
        _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) return;
    await shell.probe.syncDisplayGrid();
  }

  bool isMemberComposerSurfaceReady(String sessionId, String memberId) {
    final shell =
        _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null || !shell.activityTracker.isBootFrameReady) {
      return false;
    }
    final window = shell.probe.describeProbeWindow(scanRows: _composerProbeRows);
    return isTerminalInputSurfaceReady(
      readiness: _behaviorFor(sessionId, memberId)?.inputReadiness,
      probeWindow: window,
    );
  }

  void maybeNudgeMemberBootGate(String sessionId, String memberId) {
    final shell =
        _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) return;
    final readiness = _behaviorFor(sessionId, memberId)?.inputReadiness;
    if (readiness == null || !readiness.waitsForSurface) return;
    final window = shell.probe.describeProbeWindow(scanRows: _composerProbeRows);
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

  bool isBusy(String sessionId, String memberId) =>
      _ptyInject.isBusy(sessionId, memberId);

  void clearPending(String sessionId, String memberId) =>
      _ptyInject.clearPending(sessionId, memberId);

  void abortMemberInject(String sessionId, String memberId) {
    _ptyInject.requestAbort(sessionId, memberId);
    if (!_ptyInject.isBusy(sessionId, memberId)) {
      _ptyInject.clearAbort(sessionId, memberId);
    }
  }

  void tickRetries({
    required bool Function(PtyAutomationRetryTick tick) shouldSkip,
    required void Function(PtyAutomationRetryTick tick) onTick,
  }) {
    _ptyInject.tickRetries(shouldSkip: shouldSkip, onTick: onTick);
  }

  /// Bracketed-paste + CR for full-screen CLIs; [automation] uses grid ACK.
  Future<void> deliverMemberStdin(
    String sessionId,
    String memberId,
    String text, {
    required bool automation,
    bool latchUserTurn = true,
  }) async {
    final shell = _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
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
    if (isMailDoorbell && !_beginMailDelivery(sessionId, memberId)) return;

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
      }
      if (_deferMailDoorbellIfBooting(sessionId, memberId, shell, trimmed)) {
        return;
      }
      _trackPromptSubmitAck(
        sessionId: sessionId,
        memberId: memberId,
        text: trimmed,
        isOperatorTurn: isOperatorTurn,
      );
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
    final shell = _tabStore.openTabBySessionId(sessionId)?.memberShells[memberId];
    if (shell == null) {
      appLogger.w(
        '[session-runtime] retry-delivery skipped no-shell '
        'member=$memberId session=$sessionId',
      );
      return;
    }
    if (_ptyAckAborted(shell, sessionId: sessionId, memberId: memberId)) return;
    if (shouldSkipAutomationRetry(sessionId, memberId)) {
      dropStaleAutomationRetry(sessionId, memberId, shell);
      return;
    }
    final trimmed = notice.trim();
    if (trimmed.isEmpty) return;
    final isMailDoorbell = _isMailDoorbellText(trimmed);
    if (isMailDoorbell && !_beginMailDelivery(sessionId, memberId)) return;
    if (isMailDoorbell) {
      await shell.probe.syncDisplayGrid();
    }
    if (_deferMailDoorbellIfBooting(sessionId, memberId, shell, trimmed)) {
      return;
    }
    // Hook already confirmed this prompt was submitted — re-pasting now would
    // create a duplicate user row (the multi-bubble symptom).
    if (_promptAckTracker.isAcked(sessionId: sessionId, memberId: memberId)) {
      appLogger.d(
        '[session-runtime] retry-delivery skipped prompt-already-acked '
        'member=$memberId session=$sessionId',
      );
      _ptyInject.clearPending(sessionId, memberId);
      if (isMailDoorbell) {
        _reportMailDeliveryOutcome(
          sessionId,
          memberId,
          FullscreenPtyDeliveryOutcome.submitted,
        );
      } else {
        _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
      }
      return;
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
      await shell.input.submitFullScreenInput(trimmed, pasteSettleDelay: settle);
      if (isMailDoorbell) {
        _reportMailDeliveryOutcome(
          sessionId,
          memberId,
          FullscreenPtyDeliveryOutcome.submitted,
        );
      }
      return;
    }
    final settle = _pasteSettleForMember(
      sessionId,
      memberId,
      automation: true,
    );
    _trackPromptSubmitAck(
      sessionId: sessionId,
      memberId: memberId,
      text: trimmed,
    );
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
      isAcked: () =>
          _promptAckTracker.isAcked(sessionId: sessionId, memberId: memberId),
    );
    if (isMailDoorbell) {
      _reportMailDeliveryOutcome(sessionId, memberId, outcome);
    }
  }

  /// Default: TeamBus mailbox when a bus is installed. [directToPty] injects at
  /// the member prompt (compose landing, automation, first prompt).
  ///
  /// Returns the mailbox message id when routed via TeamBus; otherwise `null`.
  /// When [directToPty] is false and no bus is installed, returns `null`
  /// without falling back to PTY inject (caller must not treat that as success).
  Future<String?> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) async {
    if (message.trim().isEmpty) return null;
    _onUserActivity?.call(sessionId);
    if (!directToPty) {
      final bus = busForSession(sessionId);
      if (bus == null) return null;
      final id = bus.deliverUserCommand(memberId, message);
      return id.isEmpty ? null : id;
    }
    await deliverMemberStdin(
      sessionId,
      memberId,
      message,
      automation: true,
    );
    return null;
  }

  bool shouldSkipAutomationRetry(
    String sessionId,
    String memberId, {
    String? dueRetryText,
  }) {
    final bus = busForSession(sessionId);
    // due() dequeues before shouldSkip. Landing injects have no doorbell
    // obligation — without this, the guard treats them as stale and drops.
    if (dueRetryText != null && !_isMailDoorbellText(dueRetryText)) {
      return false;
    }
    return PtyAutomationDeliveryGuard.shouldSkipRetry(
      bus: bus,
      memberId: memberId,
      memberInTurn: bus?.isMemberInTurn(memberId) ?? false,
      pendingAutomationRetry: _ptyInject.hasPendingRetry(sessionId, memberId),
    );
  }

  void dropStaleAutomationRetry(
    String sessionId,
    String memberId,
    TerminalSession shell,
  ) {
    _ptyInject.clearPending(sessionId, memberId);
    shell.markUserTurnIdle();
    appLogger.d(
      '[session-runtime] automation-retry-skipped member=$memberId '
      'session=$sessionId',
    );
  }

  Future<void> retryAutomationTick(PtyAutomationRetryTick tick) async {
    final shell =
        _tabStore.openTabBySessionId(tick.sessionId)?.memberShells[tick.memberId];
    if (shell == null) return;
    if (_ptyAckAborted(
      shell,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
    )) {
      return;
    }
    if (shouldSkipAutomationRetry(
      tick.sessionId,
      tick.memberId,
      dueRetryText: tick.text,
    )) {
      dropStaleAutomationRetry(tick.sessionId, tick.memberId, shell);
      return;
    }
    if (_deferMailDoorbellIfBooting(
      tick.sessionId,
      tick.memberId,
      shell,
      tick.text,
    )) {
      return;
    }
    // Hook ACK already confirmed this prompt submitted (e.g. it landed while
    // the previous crStuck outcome was being computed) — re-pasting now would
    // duplicate the user row, so treat the delivery as done.
    if (_promptAckTracker.isAcked(
      sessionId: tick.sessionId,
      memberId: tick.memberId,
    )) {
      appLogger.d(
        '[session-runtime] automation-retry-skipped prompt-already-acked '
        'member=${tick.memberId} session=${tick.sessionId}',
      );
      _ptyInject.clearPending(tick.sessionId, tick.memberId);
      if (_isMailDoorbellText(tick.text)) {
        _reportMailDeliveryOutcome(
          tick.sessionId,
          tick.memberId,
          FullscreenPtyDeliveryOutcome.submitted,
        );
      } else {
        _markMemberTurnStartedOnSubmitSuccess(tick.sessionId, tick.memberId);
      }
      return;
    }
    final settle = _pasteSettleForMember(
      tick.sessionId,
      tick.memberId,
      automation: true,
    );
    if (!_memberUsesGridPasteAck(tick.sessionId, tick.memberId)) {
      await shell.input.submitFullScreenInput(tick.text, pasteSettleDelay: settle);
      if (_isMailDoorbellText(tick.text)) {
        _reportMailDeliveryOutcome(
          tick.sessionId,
          tick.memberId,
          FullscreenPtyDeliveryOutcome.submitted,
        );
      } else {
        _markMemberTurnStartedOnSubmitSuccess(tick.sessionId, tick.memberId);
      }
      return;
    }
    _trackPromptSubmitAck(
      sessionId: tick.sessionId,
      memberId: tick.memberId,
      text: tick.text,
      isOperatorTurn: !_isMailDoorbellText(tick.text),
    );
    final outcome = await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
      text: tick.text,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(
        shell,
        sessionId: tick.sessionId,
        memberId: tick.memberId,
      ),
      crAckConfig: _crAckForMember(tick.sessionId, tick.memberId),
      isAcked: () => _promptAckTracker.isAcked(
        sessionId: tick.sessionId,
        memberId: tick.memberId,
      ),
    );
    if (_isMailDoorbellText(tick.text)) {
      _reportMailDeliveryOutcome(tick.sessionId, tick.memberId, outcome);
    } else if (outcome == FullscreenPtyDeliveryOutcome.submitted) {
      _markMemberTurnStartedOnSubmitSuccess(tick.sessionId, tick.memberId);
    }
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
        isAcked: () =>
            _promptAckTracker.isAcked(sessionId: sessionId, memberId: memberId),
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

  /// Registers a prompt-submit ACK pending before the grid probe runs. The
  /// hook event (UserPromptSubmit) is the authoritative delivery confirmation:
  /// when it arrives, cancel any scheduled re-paste (crStuck retry storm) and
  /// treat the submit as success. The grid probe still runs as a fallback —
  /// hook-channel absence keeps today's behavior unchanged.
  void _trackPromptSubmitAck({
    required String sessionId,
    required String memberId,
    required String text,
    bool isOperatorTurn = false,
  }) {
    _promptAckTracker
        .register(sessionId: sessionId, memberId: memberId, text: text)
        .then((acked) {
          if (acked) {
            _ptyInject.clearPending(sessionId, memberId);
            if (isOperatorTurn) {
              _markMemberTurnStartedOnSubmitSuccess(sessionId, memberId);
            }
          }
        })
        .ignore();
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
      if (!_ptyInject.isBusy(sessionId, memberId)) {
        _ptyInject.clearAbort(sessionId, memberId);
      }
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
    _ptyInject.deferForBoot(sessionId, memberId, text);
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

  void _onDeliveryRetryExhausted(
    String sessionId,
    String memberId,
    FullscreenPtyDeliveryOutcome outcome,
  ) {
    final error = switch (outcome) {
      FullscreenPtyDeliveryOutcome.pasteNotFound =>
        MailboxDeliveryError.pasteNotFound,
      FullscreenPtyDeliveryOutcome.aborted => MailboxDeliveryError.aborted,
      FullscreenPtyDeliveryOutcome.crStuck ||
      FullscreenPtyDeliveryOutcome.submitted =>
        MailboxDeliveryError.crStuck,
    };
    busForSession(sessionId)?.markMailDeliveryFailed(memberId, error: error);
    _ptyInject.clearPending(sessionId, memberId);
  }
}
