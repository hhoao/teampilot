import 'dart:async';

import 'package:flutter/foundation.dart';

/// P4 §11: liveness of a single remote (ssh) target's control connection.
///
/// `degraded` = at least one heartbeat missed but not yet given up;
/// `down` = the connection is gone (missed past threshold, or a reconnect
/// failed); `reconnecting` = a reconnect attempt is in flight. A target only
/// transitions through these — the control plane (home) and other targets are
/// unaffected (drop isolation: one monitor per target).
enum RemoteConnectionStatus { connected, degraded, reconnecting, down }

/// Inputs that move a connection between states. Heartbeat ticks and reconnect
/// outcomes are reported by the (timer/SSH) driver; the reducer is pure.
enum RemoteConnectionEvent {
  heartbeatOk,
  heartbeatTimeout,
  reconnectStarted,
  reconnected,
  reconnectFailed,
  markedDown,
}

@immutable
class RemoteConnectionState {
  const RemoteConnectionState({
    required this.status,
    this.missedHeartbeats = 0,
  });

  final RemoteConnectionStatus status;

  /// Consecutive missed heartbeats since the last healthy beat. Reset to 0 on
  /// any `connected` transition.
  final int missedHeartbeats;

  static const initial =
      RemoteConnectionState(status: RemoteConnectionStatus.connected);

  bool get isHealthy => status == RemoteConnectionStatus.connected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteConnectionState &&
          status == other.status &&
          missedHeartbeats == other.missedHeartbeats;

  @override
  int get hashCode => Object.hash(status, missedHeartbeats);

  @override
  String toString() =>
      'RemoteConnectionState(${status.name}, missed=$missedHeartbeats)';
}

/// Pure state machine (no timers/IO) so transitions are exhaustively unit-tested
/// and reused by any driver (timer-based heartbeat, SSH keepalive callbacks).
class RemoteConnectionReducer {
  const RemoteConnectionReducer._();

  /// Number of consecutive missed heartbeats that flips `degraded` → `down`.
  static const defaultMaxMissedBeforeDown = 3;

  static RemoteConnectionState reduce(
    RemoteConnectionState state,
    RemoteConnectionEvent event, {
    int maxMissedBeforeDown = defaultMaxMissedBeforeDown,
  }) {
    switch (event) {
      case RemoteConnectionEvent.heartbeatOk:
        // A healthy beat recovers from degraded/down without a formal reconnect.
        return RemoteConnectionState.initial;
      case RemoteConnectionEvent.heartbeatTimeout:
        // While a reconnect is in flight, the reconnect outcome — not stray
        // heartbeat timeouts — drives the next state.
        if (state.status == RemoteConnectionStatus.reconnecting) return state;
        final missed = state.missedHeartbeats + 1;
        final status = missed >= maxMissedBeforeDown
            ? RemoteConnectionStatus.down
            : RemoteConnectionStatus.degraded;
        return RemoteConnectionState(status: status, missedHeartbeats: missed);
      case RemoteConnectionEvent.reconnectStarted:
        return RemoteConnectionState(
          status: RemoteConnectionStatus.reconnecting,
          missedHeartbeats: state.missedHeartbeats,
        );
      case RemoteConnectionEvent.reconnected:
        return RemoteConnectionState.initial;
      case RemoteConnectionEvent.reconnectFailed:
        return RemoteConnectionState(
          status: RemoteConnectionStatus.down,
          missedHeartbeats: state.missedHeartbeats,
        );
      case RemoteConnectionEvent.markedDown:
        return RemoteConnectionState(
          status: RemoteConnectionStatus.down,
          missedHeartbeats: state.missedHeartbeats,
        );
    }
  }
}

/// Stateful, stream-exposed wrapper over [RemoteConnectionReducer] for one
/// target. A driver feeds it heartbeat/reconnect events; the UI subscribes to
/// [changes]. Holds no timers/SSH itself, so it is deterministic in tests and
/// the timer/SSH driver can be swapped freely.
class RemoteConnectionMonitor {
  RemoteConnectionMonitor({
    this.maxMissedBeforeDown = RemoteConnectionReducer.defaultMaxMissedBeforeDown,
  });

  final int maxMissedBeforeDown;
  RemoteConnectionState _state = RemoteConnectionState.initial;
  final StreamController<RemoteConnectionState> _changes =
      StreamController<RemoteConnectionState>.broadcast();

  RemoteConnectionState get state => _state;
  Stream<RemoteConnectionState> get changes => _changes.stream;

  void heartbeatOk() => _apply(RemoteConnectionEvent.heartbeatOk);
  void heartbeatTimedOut() => _apply(RemoteConnectionEvent.heartbeatTimeout);
  void reconnectStarted() => _apply(RemoteConnectionEvent.reconnectStarted);
  void reconnected() => _apply(RemoteConnectionEvent.reconnected);
  void reconnectFailed() => _apply(RemoteConnectionEvent.reconnectFailed);
  void markDown() => _apply(RemoteConnectionEvent.markedDown);

  void _apply(RemoteConnectionEvent event) {
    final next = RemoteConnectionReducer.reduce(
      _state,
      event,
      maxMissedBeforeDown: maxMissedBeforeDown,
    );
    if (next == _state) return;
    _state = next;
    _changes.add(next);
  }

  Future<void> dispose() => _changes.close();
}
