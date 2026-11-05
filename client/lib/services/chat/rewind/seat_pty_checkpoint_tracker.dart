import 'package:ai_message_core/ai_message_core.dart';

import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../utils/logging/logger.dart';
import 'rewind_work_gate.dart';
import 'seat_rewind_policy.dart';
import 'seat_rewind_store.dart';

/// History/session access the PTY checkpoint tracker needs from ChatCubit.
///
/// The tracker owns baseline/deduplication state; the host only exposes what
/// the history seat/loader currently knows.
abstract interface class PtyCheckpointHost {
  AppSession? ptySessionFor(String sessionId);
  bool ptyIsAcp(AppSession session, String memberId);
  CliTool ptyCliFor(AppSession session, String memberId);
  String? ptyNativeSessionId(AppSession session, String memberId, CliTool cli);
  List<AiMessage>? ptySeatMessages(String sessionId, String historyMemberId);
  List<AiMessage>? ptyLoaderMessages(String sessionId, String historyMemberId);
  Future<void> ptyReloadSeat(String sessionId, String historyMemberId);
  Future<void> ptyWaitForHistory(String sessionId, String historyMemberId);
  Future<void> ptyCommitCheckpoint({
    required SeatRewindStore store,
    required String messageId,
    required String userMessageId,
    required String? nativeSessionId,
  });
  void ptyHistoryChanged(String sessionId);
}

/// Decides which PTY turn just closed and commits its rewind checkpoint.
///
/// Extracted from ChatCubit so baseline/wait/reload/dedupe state has one owner
/// and no longer inflates the cubit's lifecycle code.
final class SeatPtyCheckpointTracker {
  SeatPtyCheckpointTracker({
    required this.host,
    required this.policy,
    required this.gate,
  });

  final PtyCheckpointHost host;
  final SeatRewindPolicy policy;
  final RewindWorkGate gate;

  /// Last message id committed for a PTY seat (`sessionId\0memberId`).
  final _committedMessageBySeat = <String, String>{};

  /// Latest history id seen when the seat entered working.
  final _turnBaseline = <String, String>{};

  /// Runs when the shell latch rises. The first signal wins.
  void onShellTurnStarted(String sessionId, String memberId) {
    rememberBaseline(sessionId, memberId);
  }

  /// Records the latest visible id at turn start.
  void rememberBaseline(String sessionId, String memberId) {
    if (memberId.trim().isEmpty) return;
    final seatKey = _seatKey(sessionId, memberId);
    if (_turnBaseline.containsKey(seatKey)) return;
    final session = host.ptySessionFor(sessionId);
    final historyMemberId = session == null || session.isSimple ? '' : memberId;
    _turnBaseline[seatKey] =
        _observedMessageId(
          sessionId: sessionId,
          historyMemberId: historyMemberId,
        ) ??
        '';
  }

  /// Snapshot this seat for the turn that just finished.
  Future<void> checkpointTurn(String sessionId, String memberId) async {
    if (memberId.trim().isEmpty) return;
    final session = host.ptySessionFor(sessionId);
    if (session == null) return;
    if (host.ptyIsAcp(session, memberId)) return;
    final cli = host.ptyCliFor(session, memberId);
    final eligibility = policy.evaluate(
      session: session,
      memberId: memberId,
      cli: cli,
      acp: false,
    );
    if (!eligibility.allowed) return;
    final store = eligibility.store!;
    final personal = session.isSimple;
    final historyMemberId = personal ? '' : memberId;
    final seatKey = _seatKey(sessionId, memberId);
    final nativeSessionId = host.ptyNativeSessionId(session, memberId, cli);
    await gate.runSnapshot(store.gitDir, () async {
      try {
        final messageId = await _closingMessageId(
          sessionId: sessionId,
          memberId: memberId,
          historyMemberId: historyMemberId,
          seatKey: seatKey,
        );
        if (messageId == null) return;
        final userMessageId = _observedUserMessageId(
          sessionId: sessionId,
          historyMemberId: historyMemberId,
        );
        // A checkpoint with no anchor cannot drive the version control, and
        // committing it would still move `live` past the turn.
        if (userMessageId == null) return;
        if (_committedMessageBySeat[seatKey] == messageId) return;
        await host.ptyCommitCheckpoint(
          store: store,
          messageId: messageId,
          userMessageId: userMessageId,
          nativeSessionId: nativeSessionId,
        );
        _committedMessageBySeat[seatKey] = messageId;
        host.ptyHistoryChanged(sessionId);
      } on RewindTurnSkipped {
        return;
      } on Object catch (error, stackTrace) {
        appLogger.e(
          '[rewind] pty checkpoint failed session=$sessionId '
          'member=$memberId: $error',
          error: error,
          stackTrace: stackTrace,
        );
      } finally {
        // The next turn's rising edge must record a fresh start id.
        _turnBaseline.remove(seatKey);
      }
    });
  }

  String? _observedMessageId({
    required String sessionId,
    required String historyMemberId,
  }) {
    final fromSeat = _latestMessageId(
      host.ptySeatMessages(sessionId, historyMemberId),
    );
    if (fromSeat != null) return fromSeat;
    return _latestMessageId(host.ptyLoaderMessages(sessionId, historyMemberId));
  }

  String? _observedUserMessageId({
    required String sessionId,
    required String historyMemberId,
  }) {
    final fromSeat = _lastUserMessageId(
      host.ptySeatMessages(sessionId, historyMemberId),
    );
    if (fromSeat != null) return fromSeat;
    return _lastUserMessageId(
      host.ptyLoaderMessages(sessionId, historyMemberId),
    );
  }

  Future<String?> _closingMessageId({
    required String sessionId,
    required String memberId,
    required String historyMemberId,
    required String seatKey,
  }) async {
    final observed = _observedMessageId(
      sessionId: sessionId,
      historyMemberId: historyMemberId,
    );
    if (observed != null && _committedMessageBySeat[seatKey] == observed) {
      return null;
    }
    if (!_turnBaseline.containsKey(seatKey)) {
      appLogger.w(
        '[rewind] pty checkpoint skipped: turn start was not observed '
        'session=$sessionId member=$memberId',
      );
      return null;
    }
    final ready = _idThatClosedTurn(seatKey, observed);
    if (ready != null) return ready;

    try {
      await host.ptyReloadSeat(sessionId, historyMemberId);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[rewind] history seat reload failed session=$sessionId '
        'member=$memberId: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
    // A completed reload already published the closing message; waiting for
    // the loader's catch-up timeout on top of it would stall the checkpoint.
    final reloaded = _observedMessageId(
      sessionId: sessionId,
      historyMemberId: historyMemberId,
    );
    final afterReload = _idThatClosedTurn(seatKey, reloaded);
    if (afterReload != null) return afterReload;

    await host.ptyWaitForHistory(sessionId, historyMemberId);
    final retried = _observedMessageId(
      sessionId: sessionId,
      historyMemberId: historyMemberId,
    );
    if (retried != null && _committedMessageBySeat[seatKey] == retried) {
      return null;
    }
    if (!_turnBaseline.containsKey(seatKey)) return null;
    final closing = _idThatClosedTurn(seatKey, retried);
    if (closing != null) return closing;
    appLogger.w(
      '[rewind] pty checkpoint skipped: history has not observed this turn '
      'session=$sessionId member=$memberId',
    );
    return null;
  }

  String? _idThatClosedTurn(String seatKey, String? id) {
    if (id == null || id.isEmpty) return null;
    if (_committedMessageBySeat[seatKey] == id) return null;
    // No start baseline: the visible id may be the previous turn's message.
    if (!_turnBaseline.containsKey(seatKey)) return null;
    if (id == _turnBaseline[seatKey]) return null;
    return id;
  }

  static String _seatKey(String sessionId, String memberId) =>
      '$sessionId\u0000$memberId';

  static String? _latestMessageId(List<AiMessage>? messages) {
    if (messages == null || messages.isEmpty) return null;
    final id = messages.last.id.trim();
    return id.isEmpty ? null : id;
  }

  static String? _lastUserMessageId(List<AiMessage>? messages) {
    if (messages == null) return null;
    for (final message in messages.reversed) {
      if (message.role != AiRole.user) continue;
      final id = message.id.trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }
}
