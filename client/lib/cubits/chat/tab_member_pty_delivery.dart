import 'package:flutter/foundation.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../services/cli/registry/capabilities/terminal_behavior_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/team_bus/mailbox_delivery.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/terminal/fullscreen_cr_ack_config.dart';
import '../../services/terminal/fullscreen_pty_automation.dart';
import '../../services/terminal/member_pty_inject_service.dart';
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
    MemberPtyInjectService? ptyInject,
  }) : _tabStore = tabStore,
       _shellFactory = shellFactory,
       _globalPresets = globalPresets,
       _activeTeam = activeTeam,
       _isClosed = isClosed,
       _coordinationFactory = coordinationFactory,
       _onAfterTurnLatched = onAfterTurnLatched {
    _ptyInject =
        ptyInject ??
        MemberPtyInjectService(
          onDeliveryRetryExhausted: _onDeliveryRetryExhausted,
        );
  }

  final ChatTabStore _tabStore;
  final ChatSessionShellFactory _shellFactory;
  final List<CliPreset> Function() _globalPresets;
  final TeamProfile? Function() _activeTeam;
  final bool Function() _isClosed;
  final TabMemberCoordinationFactory _coordinationFactory;
  final void Function(String sessionId, String memberId)? _onAfterTurnLatched;
  late final MemberPtyInjectService _ptyInject;

  TeamBus? busForSession(String sessionId) =>
      _tabStore.openTabBySessionId(sessionId)?.teamBus;

  bool hasPendingRetry(String sessionId, String memberId) =>
      _ptyInject.hasPendingRetry(sessionId, memberId);

  bool isBusy(String sessionId, String memberId) =>
      _ptyInject.isBusy(sessionId, memberId);

  void clearPending(String sessionId, String memberId) =>
      _ptyInject.clearPending(sessionId, memberId);

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
    if (_ptyAckAborted(shell)) return;
    if (shouldSkipAutomationRetry(sessionId, memberId)) {
      dropStaleAutomationRetry(sessionId, memberId, shell);
      return;
    }
    final trimmed = notice.trim();
    if (trimmed.isEmpty) return;
    final isMailDoorbell = _isMailDoorbellText(trimmed);
    if (isMailDoorbell && !_beginMailDelivery(sessionId, memberId)) return;

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
    final outcome = await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: sessionId,
      memberId: memberId,
      text: trimmed,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(shell),
      crAckConfig: _crAckForMember(sessionId, memberId),
    );
    if (isMailDoorbell) {
      _reportMailDeliveryOutcome(sessionId, memberId, outcome);
    }
  }

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
    await deliverMemberStdin(
      sessionId,
      memberId,
      message,
      automation: true,
    );
  }

  bool shouldSkipAutomationRetry(String sessionId, String memberId) {
    final bus = busForSession(sessionId);
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
    if (_ptyAckAborted(shell)) return;
    if (shouldSkipAutomationRetry(tick.sessionId, tick.memberId)) {
      dropStaleAutomationRetry(tick.sessionId, tick.memberId, shell);
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
    final outcome = await _ptyInject.retry(
      input: shell.input,
      probe: shell.probe,
      sessionId: tick.sessionId,
      memberId: tick.memberId,
      text: tick.text,
      pasteSettle: settle,
      aborted: () => _ptyAckAborted(shell),
      crAckConfig: _crAckForMember(tick.sessionId, tick.memberId),
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
        aborted: () => _ptyAckAborted(shell),
        crAckConfig: _crAckForMember(sessionId, memberId),
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

  bool _ptyAckAborted(TerminalSession shell) =>
      _isClosed() || !shell.isConnected;

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

  static bool _isMailDoorbellText(String text) => text == TeamBus.doorbellNotice;

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
