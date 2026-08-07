import 'dart:async';

import '../../services/session/ai_history_loader.dart';
import '../../services/session/history_seat_key.dart';
import '../../services/team_bus/persistence/bus_message_log.dart';
import '../ai_history_seat.dart';

/// Per-session history store: one [AiHistorySeat] per `memberId`, owned by a
/// single session. The pod owns one of these; SessionChatView binds a member
/// seat through it instead of the global AiHistoryCubit registry.
class HistoryStore {
  HistoryStore({
    required AiHistoryLoader loader,
    Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
    loadMailboxRecords,
  }) : _loader = loader,
       _loadMailboxRecords = loadMailboxRecords;

  final AiHistoryLoader _loader;
  final Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
  _loadMailboxRecords;
  final Map<String, AiHistorySeat> _seats = {};
  final Map<String, StreamSubscription<AiHistoryState>> _seatSubs = {};

  AiHistoryLoader get loader => _loader;

  AiHistorySeat memberSeat({
    required String sessionId,
    required String memberId,
  }) {
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: memberId,
    );
    final existing = _seats[key];
    if (existing != null) return existing;

    final seat = AiHistorySeat(
      loader: _loader,
      onTranscriptApplied: (sid, mid) =>
          _consumeSeedPendingIfMatching(sid, mid),
      loadMailboxRecords: _loadMailboxRecords,
    );
    _seats[key] = seat;
    // Keep seat emits flowing to any host that listens; SessionChatView binds
    // the seat directly (BlocBuilder<AiHistorySeat, ...>).
    _seatSubs[key] = seat.stream.listen((_) {});
    return seat;
  }

  AiHistorySeat? seatOf({
    required String sessionId,
    required String memberId,
  }) {
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: memberId,
    );
    return _seats[key];
  }

  /// Landing create+send may finish before History loads the new seat. Survives
  /// [AiHistorySeat.clearPendings]; consumed when that seat loads.
  final Map<String, String> _seedPendingByKey = {};

  void seedPendingUser({
    required String sessionId,
    required String memberId,
    required String text,
  }) {
    final trimmed = text.trim();
    if (sessionId.trim().isEmpty || trimmed.isEmpty) return;
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: memberId,
    );
    final seat = _seats[key];
    if (seat != null && _seatMatchesKey(seat, key)) {
      seat.enqueuePendingUser(trimmed);
      _seedPendingByKey.remove(key);
      return;
    }
    _seedPendingByKey[key] = trimmed;
  }

  void _consumeSeedPendingIfMatching(String sessionId, String memberId) {
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: memberId,
    );
    final seedText = _seedPendingByKey.remove(key);
    if (seedText == null) return;
    final seat = _seats[key];
    if (seat == null) return;
    seat.enqueuePendingUser(seedText);
  }

  bool _seatMatchesKey(AiHistorySeat seat, String key) {
    final sid = seat.state.sessionId;
    if (sid == null || sid.isEmpty) return false;
    return historySeatKey(
          sessionId: sid,
          selectedMemberId: seat.state.memberId ?? '',
        ) ==
        key;
  }

  /// Drop a landing seed and any matching optimistic pending when send fails.
  void cancelSeedPendingUser({
    required String sessionId,
    required String text,
  }) {
    final trimmed = text.trim();
    final prefix = '${sessionId.trim()}|';
    for (final entryKey in _seedPendingByKey.keys.toList()) {
      if (!entryKey.startsWith(prefix)) continue;
      final seedText = _seedPendingByKey[entryKey];
      if (seedText != null && seedText == trimmed) {
        _seedPendingByKey.remove(entryKey);
      }
    }
    for (final entry in _seats.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      entry.value.removePendingMatching(trimmed);
    }
  }

  Future<void> disposeSeats(String sessionId) async {
    final prefix = '${sessionId.trim()}|';
    final keys = _seats.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keys) {
      final sub = _seatSubs.remove(key);
      await sub?.cancel();
      final seat = _seats.remove(key);
      await seat?.close();
    }
    for (final key in _seedPendingByKey.keys.toList()) {
      if (key.startsWith(prefix)) _seedPendingByKey.remove(key);
    }
  }

  Future<void> close() async {
    for (final key in _seats.keys.toList()) {
      final sub = _seatSubs.remove(key);
      await sub?.cancel();
      final seat = _seats.remove(key);
      await seat?.close();
    }
    _seedPendingByKey.clear();
  }
}
