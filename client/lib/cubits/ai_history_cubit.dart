import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_session.dart';
import '../models/team_config.dart';
import '../models/workspace_launch_context.dart';
import '../services/session/ai_history_loader.dart';
import '../services/session/ai_history_pending_text.dart';
import '../services/session/history_seat_key.dart';
import '../services/team_bus/persistence/bus_message_log.dart';
import 'ai_history_seat.dart';

export 'ai_history_seat.dart'
    show AiHistorySeat, AiHistoryState, AiHistoryViewStatus;

/// App-wide History registry: one [AiHistorySeat] per `sessionId|shellMemberId`.
///
/// Temporary: [state] mirrors the last-loaded / focused seat so existing
/// BlocBuilder / unit tests keep working until SessionChatView binds seats.
class AiHistoryCubit extends Cubit<AiHistoryState> {
  AiHistoryCubit({
    required AiHistoryLoader loader,
    Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
    loadMailboxRecords,
  }) : _loader = loader,
       _loadMailboxRecords = loadMailboxRecords,
       super(const AiHistoryState());

  /// Alias for [AiHistorySeat.tipHoldAfterAssistant] (tests / callers).
  static const tipHoldAfterAssistant = AiHistorySeat.tipHoldAfterAssistant;

  final AiHistoryLoader _loader;
  final Future<List<LoggedMessage>> Function(String sessionId, String memberId)?
  _loadMailboxRecords;
  final Map<String, AiHistorySeat> _seats = {};
  final Map<String, StreamSubscription<AiHistoryState>> _seatSubs = {};

  /// Landing create+send may finish before History loads the new seat.
  /// Survives seat [AiHistorySeat.clearPendings]; consumed when that seat loads.
  final Map<String, String> _seedPendingByKey = {};

  String? _focusedSeatKey;

  /// Shared loader for live-refresh watch-meta resolve.
  AiHistoryLoader get loader => _loader;

  AiHistorySeat? get _focusedSeat {
    final key = _focusedSeatKey;
    if (key == null) return null;
    return _seats[key];
  }

  /// True when the focused seat has a held assistant tip.
  bool get hasHeldAssistantTip =>
      _focusedSeat?.hasHeldAssistantTip ?? false;

  /// Subagent attachment index for the focused seat (empty when none).
  Map<String, AiSubagentAttachment> get subagentAttachments =>
      _focusedSeat?.subagentAttachments ?? const {};

  AiHistorySeat ensureSeat({
    required String sessionId,
    required String selectedMemberId,
  }) {
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: selectedMemberId,
    );
    final existing = _seats[key];
    if (existing != null) return existing;

    final seat = AiHistorySeat(
      loader: _loader,
      onTranscriptApplied: _consumeSeedPendingIfMatching,
      loadMailboxRecords: _loadMailboxRecords,
    );
    _seats[key] = seat;
    // Tip-hold timer and other async seat emits must reach facade listeners.
    _seatSubs[key] = seat.stream.listen((_) => _mirrorSeat(key, seat));
    return seat;
  }

  AiHistorySeat? seatOf({
    required String sessionId,
    required String selectedMemberId,
  }) {
    final key = historySeatKey(
      sessionId: sessionId,
      selectedMemberId: selectedMemberId,
    );
    return _seats[key];
  }

  void _mirrorSeat(String key, AiHistorySeat seat) {
    if (isClosed || _focusedSeatKey != key) return;
    emit(seat.state);
  }

  Future<void> load({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final key = historySeatKey(
      sessionId: session.sessionId,
      selectedMemberId: memberId,
    );
    final seat = ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: memberId,
    );
    _focusedSeatKey = key;
    // Start seat load synchronously through its first await (emits loading),
    // then mirror before this facade method yields — so callers that do
    // `final f = cubit.load(...); expect(cubit.state.loading)` still work.
    final future = seat.load(
      session: session,
      memberId: memberId,
      launchContext: launchContext,
      team: team,
      workingDirectory: workingDirectory,
      force: force,
    );
    _mirrorSeat(key, seat);
    await future;
    _mirrorSeat(key, seat);
  }

  /// Live refresh for the focused / last-loaded seat (Task 4 binds per-seat).
  Future<void> softReload() async {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    final future = seat.softReload();
    _mirrorSeat(key, seat);
    await future;
    _mirrorSeat(key, seat);
  }

  /// Remerge read mailbox mail into a seat's timeline without a CLI reload.
  ///
  /// Hosts pass [sessionId] / [selectedMemberId] to target a specific seat;
  /// omit both to refresh the focused / last-loaded seat.
  Future<void> refreshMailboxTimeline({
    String? sessionId,
    String? selectedMemberId,
  }) async {
    final AiHistorySeat? seat;
    final String? key;
    if (sessionId != null && selectedMemberId != null) {
      key = historySeatKey(
        sessionId: sessionId,
        selectedMemberId: selectedMemberId,
      );
      seat = _seats[key];
    } else {
      key = _focusedSeatKey;
      seat = _focusedSeat;
    }
    if (seat == null || key == null) return;
    final future = seat.refreshMailboxTimeline();
    if (_focusedSeatKey == key) _mirrorSeat(key, seat);
    await future;
    if (_focusedSeatKey == key) _mirrorSeat(key, seat);
  }

  /// Review remount: soft when already ready for this seat, else cold load.
  Future<void> softReloadOrLoad({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    final key = historySeatKey(
      sessionId: session.sessionId,
      selectedMemberId: memberId,
    );
    final seat = ensureSeat(
      sessionId: session.sessionId,
      selectedMemberId: memberId,
    );
    _focusedSeatKey = key;
    final future = seat.softReloadOrLoad(
      session: session,
      memberId: memberId,
      launchContext: launchContext,
      team: team,
      workingDirectory: workingDirectory,
    );
    _mirrorSeat(key, seat);
    await future;
    _mirrorSeat(key, seat);
  }

  /// Soft-reload every open seat for [sessionId] (ready → soft; else force).
  Future<void> softReloadIfSession(String sessionId) async {
    final seats = _seatsForSession(sessionId).toList();
    if (seats.isEmpty) {
      _loader.invalidate(sessionId: sessionId);
      return;
    }
    _loader.invalidate(sessionId: sessionId);
    for (final seat in seats) {
      if (seat.state.status == AiHistoryViewStatus.ready) {
        await seat.softReload();
      } else {
        await seat.invalidateAndReload(sessionId);
      }
    }
    final focused = _focusedSeat;
    final key = _focusedSeatKey;
    if (focused != null && key != null) _mirrorSeat(key, focused);
  }

  void enqueuePendingUser(String text) {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.enqueuePendingUser(text);
    _mirrorSeat(key, seat);
  }

  /// Optimistic first bubble for landing create+send that stays on Chat.
  ///
  /// If that seat is already showing, enqueues immediately. Otherwise stores a
  /// seed keyed by [historySeatKey] and applies when that seat finishes loading.
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
      if (_focusedSeatKey == key) _mirrorSeat(key, seat);
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
    if (_focusedSeatKey == key) _mirrorSeat(key, seat);
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
    final prefix = '$sessionId|';
    final norm = normalizeAiHistoryPendingText(trimmed);
    for (final entryKey in _seedPendingByKey.keys.toList()) {
      if (!entryKey.startsWith(prefix)) continue;
      final seedText = _seedPendingByKey[entryKey];
      if (seedText != null &&
          normalizeAiHistoryPendingText(seedText) == norm) {
        _seedPendingByKey.remove(entryKey);
      }
    }
    for (final seat in _seatsForSession(sessionId)) {
      seat.removePendingMatching(trimmed);
    }
    final focused = _focusedSeat;
    final key = _focusedSeatKey;
    if (focused != null && key != null) {
      focused.removePendingMatching(trimmed);
      _mirrorSeat(key, focused);
    }
  }

  void removePendingMatching(String text) {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.removePendingMatching(text);
    _mirrorSeat(key, seat);
  }

  void setAwaitingAssistant(bool value) {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.setAwaitingAssistant(value);
    _mirrorSeat(key, seat);
  }

  void flushHeldTip({bool endAwaiting = false}) {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.flushHeldTip(endAwaiting: endAwaiting);
    _mirrorSeat(key, seat);
  }

  void clearPendings() {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.clearPendings();
    _mirrorSeat(key, seat);
  }

  Future<void> invalidateAndReload(String sessionId) async {
    _loader.invalidate(sessionId: sessionId);
    final seats = _seatsForSession(sessionId).toList();
    for (final seat in seats) {
      await seat.invalidateAndReload(sessionId);
    }
    final focused = _focusedSeat;
    final key = _focusedSeatKey;
    if (focused != null && key != null) _mirrorSeat(key, focused);
  }

  void invalidateSession(String sessionId) {
    _loader.invalidate(sessionId: sessionId);
  }

  void loadOlder() {
    final seat = _focusedSeat;
    final key = _focusedSeatKey;
    if (seat == null || key == null) return;
    seat.loadOlder();
    _mirrorSeat(key, seat);
  }

  void disposeSeatsForSession(String sessionId) {
    final prefix = '$sessionId|';
    final keys = _seats.keys
        .where((k) => k.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      final seat = _seats.remove(key);
      final sub = _seatSubs.remove(key);
      unawaited(sub?.cancel() ?? Future<void>.value());
      unawaited(seat?.close() ?? Future<void>.value());
    }
    for (final key in _seedPendingByKey.keys.toList(growable: false)) {
      if (key.startsWith(prefix)) _seedPendingByKey.remove(key);
    }
    if (_focusedSeatKey != null && _focusedSeatKey!.startsWith(prefix)) {
      _focusedSeatKey = null;
      if (!isClosed) emit(const AiHistoryState());
    }
  }

  void clear() {
    for (final key in _seats.keys.toList(growable: false)) {
      final seat = _seats.remove(key);
      final sub = _seatSubs.remove(key);
      unawaited(sub?.cancel() ?? Future<void>.value());
      unawaited(seat?.close() ?? Future<void>.value());
    }
    _seedPendingByKey.clear();
    _focusedSeatKey = null;
    if (!isClosed) emit(const AiHistoryState());
  }

  Iterable<AiHistorySeat> _seatsForSession(String sessionId) {
    final prefix = '$sessionId|';
    return _seats.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => e.value);
  }

  @override
  Future<void> close() async {
    for (final key in _seats.keys.toList(growable: false)) {
      final seat = _seats.remove(key);
      final sub = _seatSubs.remove(key);
      await sub?.cancel();
      await seat?.close();
    }
    _seedPendingByKey.clear();
    _focusedSeatKey = null;
    return super.close();
  }
}
