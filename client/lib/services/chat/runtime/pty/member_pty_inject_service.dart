import 'dart:async';

import 'fullscreen_cr_ack_config.dart';
import 'fullscreen_pty_automation.dart';
import 'fullscreen_pty_submission_machine.dart';
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

  /// One state machine per seat for the *current* doorbell payload. Reused by
  /// [retry] so a re-ring never re-pastes an already-staged message and never
  /// leaves `staging` once the needle is confirmed ([FullscreenPtySubmission]).
  final Map<String, FullscreenPtySubmission> _machines = {};

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

  /// First mailbox delivery: begin a new submission machine, then drive it.
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
  }) {
    final key = _key(sessionId, memberId);
    final machine = FullscreenPtySubmission(
      budget: _submissionBudget(),
      now: DateTime.now,
    );
    machine.begin();
    _machines[key] = machine;
    return _run(
      sessionId,
      memberId,
      () => _automation.continueSubmission(
        machine,
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
  }

  /// TeamBus-owned retry: continues the same submission machine — re-staging
  /// while the needle is absent, send-only once the needle is confirmed
  /// (see [FullscreenPtyAutomation.continueSubmission]).
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
  }) {
    final key = _key(sessionId, memberId);
    final machine =
        _machines[key] ??
        (FullscreenPtySubmission(budget: _submissionBudget(), now: DateTime.now)
          ..begin());
    _machines[key] = machine;
    return _run(
      sessionId,
      memberId,
      () => _automation.continueSubmission(
        machine,
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
  }

  FullscreenPtySubmissionBudget _submissionBudget() =>
      _automation.submissionBudget();

  Future<FullscreenPtyDeliveryOutcome> _run(
    String sessionId,
    String memberId,
    Future<FullscreenPtyDeliveryOutcome> Function() action,
  ) async {
    final key = _key(sessionId, memberId);
    _activeCounts[key] = (_activeCounts[key] ?? 0) + 1;
    try {
      final outcome = await action();
      if (outcome != FullscreenPtyDeliveryOutcome.crStuck &&
          outcome != FullscreenPtyDeliveryOutcome.pasteNotFound) {
        _machines.remove(key);
      }
      return outcome;
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
