import 'dart:async';

import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_pty_automation.dart';
import 'terminal_fullscreen_pty_port.dart';
import 'terminal_input_controller.dart';
import 'terminal_screen_probe_controller.dart';

/// Performs one mailbox full-screen PTY injection.
///
/// Retry policy belongs to TeamBus, and human prompt delivery belongs to
/// PromptDeliveryCoordinator. This service intentionally owns neither a retry
/// queue nor a per-seat lock.
final class MemberPtyInjectService {
  MemberPtyInjectService({FullscreenPtyAutomation? automation})
    : _automation = automation ?? FullscreenPtyAutomation();

  final FullscreenPtyAutomation _automation;
  final Set<String> _abortRequested = <String>{};
  final Map<String, int> _activeCounts = <String, int>{};

  void requestAbort(String sessionId, String memberId) {
    _abortRequested.add(_key(sessionId, memberId));
  }

  bool isAbortRequested(String sessionId, String memberId) =>
      _abortRequested.contains(_key(sessionId, memberId));

  bool isDelivering(String sessionId, String memberId) =>
      (_activeCounts[_key(sessionId, memberId)] ?? 0) > 0;

  void clearAbort(String sessionId, String memberId) {
    _abortRequested.remove(_key(sessionId, memberId));
  }

  /// First mailbox delivery: clear, paste, then issue one CR.
  Future<FullscreenPtyDeliveryOutcome> deliver({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required String sessionId,
    required String memberId,
    required String text,
    required Duration pasteSettle,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
    Stream<void>? painted,
  }) => _run(
    sessionId,
    memberId,
    () => _automation.deliverPasteAndSubmit(
      port: _port(
        input: input,
        probe: probe,
        sessionId: sessionId,
        memberId: memberId,
        aborted: aborted,
        crAckConfig: crAckConfig,
        painted: painted,
      ),
      text: text,
      pasteSettle: pasteSettle,
    ),
  );

  /// TeamBus-owned retry: CR-only when paste is already staged; otherwise
  /// re-pastes (see [FullscreenPtyAutomation.retry]).
  Future<FullscreenPtyDeliveryOutcome> retry({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required String sessionId,
    required String memberId,
    required String text,
    required Duration pasteSettle,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
    Stream<void>? painted,
  }) => _run(
    sessionId,
    memberId,
    () => _automation.retry(
      port: _port(
        input: input,
        probe: probe,
        sessionId: sessionId,
        memberId: memberId,
        aborted: aborted,
        crAckConfig: crAckConfig,
        painted: painted,
      ),
      text: text,
      pasteSettle: pasteSettle,
    ),
  );

  Future<FullscreenPtyDeliveryOutcome> _run(
    String sessionId,
    String memberId,
    Future<FullscreenPtyDeliveryOutcome> Function() action,
  ) async {
    final key = _key(sessionId, memberId);
    _activeCounts[key] = (_activeCounts[key] ?? 0) + 1;
    try {
      return await action();
    } finally {
      final remaining = (_activeCounts[key] ?? 1) - 1;
      if (remaining > 0) {
        _activeCounts[key] = remaining;
      } else {
        _activeCounts.remove(key);
        _abortRequested.remove(key);
      }
    }
  }

  TerminalFullscreenPtyPort _port({
    required TerminalInputController input,
    required TerminalScreenProbeController probe,
    required String sessionId,
    required String memberId,
    required bool Function() aborted,
    required FullscreenCrAckConfig crAckConfig,
    Stream<void>? painted,
  }) => TerminalFullscreenPtyPort(
    input: input,
    probe: probe,
    aborted: () => isAbortRequested(sessionId, memberId) || aborted(),
    crAckConfig: crAckConfig,
    painted: painted,
  );

  static String _key(String sessionId, String memberId) =>
      '$sessionId:$memberId';
}
