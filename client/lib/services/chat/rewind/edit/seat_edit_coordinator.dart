import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../models/pending_branch_edit.dart';
import 'edit_operation.dart';
import 'edit_transport.dart';

/// Runs one edit transaction on behalf of [SeatEditCoordinator].
///
/// Implemented by `ChatCubit` so the coordinator stays free of the rewind
/// graph, terminals, and delivery plumbing.
typedef SeatEditRunner = Future<void> Function({
  required String sessionId,
  required String memberId,
  required String userMessageId,
  required String text,
  required void Function(EditPhase phase) onPhase,
  required bool Function() aborted,
});

/// One seat's edited-message resend: the single owner of its phase, optimistic
/// bubble, draft, and cancellation.
///
/// [submit] returns as soon as the edit is accepted, so the editor closes
/// immediately; the transaction then runs detached and publishes phases. The
/// transcript holds its old branch while [holdsTranscript] is true, so the
/// restore's replay never paints an intermediate state.
final class SeatEditCoordinator extends ChangeNotifier {
  SeatEditCoordinator({
    required this.sessionId,
    required SeatEditRunner run,
    this.transportFor,
    this.watchdog = const Duration(seconds: 30),
  }) : _run = run;

  /// Picks the executor for one seat: null runs locally, non-null delegates to
  /// the desktop authority that owns the runtime.
  final SeatEditTransport? Function(String memberId)? transportFor;

  final String sessionId;
  final SeatEditRunner _run;

  /// Settles a delivered edit whose prompt never shows up in the transcript.
  final Duration watchdog;

  EditOperation? _operation;
  String? _editingMessageId;
  String? _draft;
  var _abortRequested = false;
  var _reopenEditorOnFailure = false;
  Timer? _timer;
  var _serial = 0;
  Future<void>? _settled;
  SeatEditTransport? _transport;
  StreamSubscription<EditOperation>? _remoteSub;

  /// The transaction to render, if any.
  EditOperation? get operation => _operation;

  /// Completes when the running transaction settles. UI never awaits this; it
  /// exists for retry chaining and tests.
  Future<void>? get settled => _settled;

  /// Id of the message whose inline editor is open (desktop) or dimmed
  /// (mobile).
  String? get editingMessageId => _editingMessageId;

  /// Draft kept so a failed edit reopens with the author's text.
  String? get draft => _draft;

  bool get isActive => _operation?.phase.isActive ?? false;

  bool get holdsTranscript => _operation?.phase.holdsTranscript ?? false;

  bool get isCancellable => _operation?.phase.isCancellable ?? false;

  /// The edited text shown in place of the old message while the resend runs.
  PendingBranchEdit? get pending {
    final op = _operation;
    if (op == null || !op.phase.keepsPendingBubble) return null;
    return PendingBranchEdit(messageId: op.messageId, text: op.text);
  }

  /// Accepts the edit and returns immediately; the resend runs in the
  /// background and is observable through [operation].
  Future<bool> submit({
    required String messageId,
    required String memberId,
    required String text,
    bool reopenEditorOnFailure = false,
    String? operationId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (isActive) return false;
    _timer?.cancel();
    _timer = null;
    _abortRequested = false;
    _reopenEditorOnFailure = reopenEditorOnFailure;
    _transport = transportFor?.call(memberId);
    _editingMessageId = null;
    _draft = null;
    final op = EditOperation(
      id: operationId?.trim().isNotEmpty == true
          ? operationId!.trim()
          : 'edit-${++_serial}',
      sessionId: sessionId,
      memberId: memberId,
      messageId: messageId,
      text: trimmed,
      phase: EditPhase.queued,
      startedAt: DateTime.now(),
    );
    _operation = op;
    notifyListeners();
    final run = _execute(op);
    _settled = run;
    unawaited(run);
    return true;
  }

  /// Stops the operation at the next phase boundary (compose Stop).
  void cancel() {
    final op = _operation;
    if (op == null || !op.phase.isCancellable) return;
    _abortRequested = true;
    final transport = _transport;
    if (transport != null) {
      // The authority decides where the boundary is; its cancelled/failed
      // phase settles this operation.
      unawaited(transport.cancel(op.id));
      return;
    }
    if (op.phase == EditPhase.queued) {
      _settle(EditPhase.cancelled, failure: EditFailure.cancelled);
    }
  }

  /// Resends the same text after a failure, without reopening the editor.
  Future<bool> retry() async {
    final op = _operation;
    if (op == null || !op.phase.allowsRetry) return false;
    final reopen = _reopenEditorOnFailure;
    return submit(
      messageId: op.messageId,
      memberId: op.memberId,
      text: op.text,
      reopenEditorOnFailure: reopen,
    );
  }

  /// The runtime published the resent prompt: the optimistic bubble is spent.
  void markLanded() {
    final op = _operation;
    if (op == null || op.phase.isTerminal) return;
    _timer?.cancel();
    _timer = null;
    _settle(EditPhase.confirmed);
  }

  /// Drops the operation without recording an outcome (runtime swap, teardown).
  void clear() {
    _timer?.cancel();
    _timer = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _transport = null;
    _abortRequested = false;
    _operation = null;
    _editingMessageId = null;
    _draft = null;
    notifyListeners();
  }

  void openEditor(String messageId) {
    _editingMessageId = messageId;
    notifyListeners();
  }

  void cancelEditor() {
    _editingMessageId = null;
    _draft = null;
    notifyListeners();
  }

  /// A runtime swap closes the inline editor but keeps the draft for a failure.
  void runtimeSwapped() {
    if (_editingMessageId == null) return;
    _editingMessageId = null;
    notifyListeners();
  }

  Future<void> _execute(EditOperation op) async {
    final transport = _transport;
    if (transport != null) return _executeRemote(op, transport);
    try {
      await _run(
        sessionId: op.sessionId,
        memberId: op.memberId,
        userMessageId: op.messageId,
        text: op.text,
        onPhase: _advance,
        aborted: () => _abortRequested,
      );
      _advance(EditPhase.awaitingReplay);
      if (_operation?.phase == EditPhase.awaitingReplay) _scheduleWatchdog();
    } on SeatEditCancelled {
      _settle(EditPhase.cancelled, failure: EditFailure.cancelled);
    } on Object catch (error) {
      _settle(
        EditPhase.failed,
        failure: EditFailure.deliveryFailed,
        detail: '$error',
      );
    }
  }

  /// Delegated run: the authority publishes phases; this side never restores,
  /// relaunches, or injects anything.
  Future<void> _executeRemote(
    EditOperation op,
    SeatEditTransport transport,
  ) async {
    _remoteSub = transport.operations
        .where((remote) => remote.id == op.id)
        .listen((remote) {
          if (_operation?.id != op.id) return;
          if (remote.phase.isTerminal) {
            _settle(remote.phase, failure: remote.failure);
          } else {
            _advance(remote.phase);
          }
        });
    try {
      final accepted = await transport.submit(
        operationId: op.id,
        messageId: op.messageId,
        text: op.text,
      );
      if (!accepted && _operation?.id == op.id && !isActive && _operation == op) {
        return;
      }
      if (!accepted && _operation?.id == op.id && !(_operation!.phase.isTerminal)) {
        _settle(
          EditPhase.failed,
          failure: EditFailure.deliveryFailed,
          detail: 'intent_rejected',
        );
      }
    } on Object catch (error) {
      if (_operation?.id != op.id || _operation!.phase.isTerminal) return;
      _settle(
        EditPhase.failed,
        failure: EditFailure.deliveryFailed,
        detail: '$error',
      );
    }
  }

  void _advance(EditPhase phase) {
    final op = _operation;
    if (op == null || op.phase.isTerminal) return;
    if (phase.index <= op.phase.index) return;
    _operation = op.copyWith(phase: phase);
    notifyListeners();
  }

  void _settle(
    EditPhase phase, {
    EditFailure? failure,
    String? detail,
  }) {
    final op = _operation;
    if (op == null) return;
    _timer?.cancel();
    _timer = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _transport = null;
    _abortRequested = false;
    _operation = op.copyWith(phase: phase, failure: failure, detail: detail);
    if (phase == EditPhase.failed && _reopenEditorOnFailure) {
      // Desktop inline editor: hand the draft back instead of losing the text.
      _editingMessageId = op.messageId;
      _draft = op.text;
    } else if (phase != EditPhase.confirmed) {
      _editingMessageId = null;
    }
    notifyListeners();
  }

  void _scheduleWatchdog() {
    if (watchdog <= Duration.zero) return;
    _timer = Timer(watchdog, markLanded);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    super.dispose();
  }
}
