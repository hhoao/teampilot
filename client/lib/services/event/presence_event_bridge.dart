import 'agent_presence_event.dart';
import 'agent_presence_sink.dart';

/// Deduping publish edge: turns repeated poll recomputations into events only
/// when a seat's availability value actually changes.
///
/// Callers recompute availability on every poll and call
/// [reportAvailability]; this class compares against the last value it
/// reported for that seat and publishes through [sink] only on a change.
///
/// Semantics:
/// - A first report for a seat (no baseline) counts as a change and IS
///   published — consumers need the initial value.
/// - Passing `null` means "this seat currently has no availability"
///   (disconnected): it clears the internal baseline and publishes
///   [AgentPresenceKind.cleared] when a baseline existed. When there was no
///   baseline, nothing is published (avoids unbound-seat tombstone spam).
///   Because the baseline is cleared, a re-report of the same value after a
///   `null` publishes again (fresh baseline).
/// - [forget] clears the baseline so the next report publishes.
/// - [dispose] stops all publishing.
final class PresenceEventBridge {
  PresenceEventBridge({required AgentPresenceSink sink, DateTime Function()? clock})
      : _sink = sink,
        _clock = clock ?? DateTime.now;

  final AgentPresenceSink _sink;
  final DateTime Function() _clock;

  /// Last reported availability per seat — the deduping baseline.
  final Map<PresenceSeatKey, AgentPresenceKind> _last = {};

  bool _disposed = false;

  /// Reports the current [availability] for [seat], publishing an event only
  /// when it differs from the last reported value. A `null` [availability]
  /// clears the baseline and publishes [AgentPresenceKind.cleared] when a
  /// baseline existed (see class docs).
  void reportAvailability(PresenceSeatKey seat, AgentPresenceKind? availability) {
    if (_disposed) return;
    if (availability == null) {
      final had = _last.remove(seat);
      if (had == null) return;
      _sink.publish(AgentPresenceEvent(
        seat: seat,
        eventKind: AgentPresenceKind.cleared,
        timestamp: _clock(),
      ));
      return;
    }
    if (_last[seat] == availability) return;
    _last[seat] = availability;
    _sink.publish(AgentPresenceEvent(
      seat: seat,
      eventKind: availability,
      timestamp: _clock(),
    ));
  }

  /// Drops [seat]'s baseline (unbind / session closed) so that its next report
  /// is published as a first value. Idempotent.
  void forget(PresenceSeatKey seat) {
    _last.remove(seat);
  }

  /// Stops all publishing. Idempotent.
  void dispose() {
    _disposed = true;
    _last.clear();
  }
}
