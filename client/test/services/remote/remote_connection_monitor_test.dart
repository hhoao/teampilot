import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/remote/remote_connection_monitor.dart';

void main() {
  group('RemoteConnectionReducer', () {
    RemoteConnectionState reduce(
      RemoteConnectionState s,
      RemoteConnectionEvent e, {
      int max = 3,
    }) =>
        RemoteConnectionReducer.reduce(s, e, maxMissedBeforeDown: max);

    test('one missed heartbeat → degraded; threshold → down', () {
      var s = RemoteConnectionState.initial;
      s = reduce(s, RemoteConnectionEvent.heartbeatTimeout);
      expect(s.status, RemoteConnectionStatus.degraded);
      expect(s.missedHeartbeats, 1);
      s = reduce(s, RemoteConnectionEvent.heartbeatTimeout);
      expect(s.status, RemoteConnectionStatus.degraded);
      s = reduce(s, RemoteConnectionEvent.heartbeatTimeout);
      expect(s.status, RemoteConnectionStatus.down);
      expect(s.missedHeartbeats, 3);
    });

    test('a healthy beat recovers from degraded and resets the counter', () {
      var s = const RemoteConnectionState(
        status: RemoteConnectionStatus.degraded,
        missedHeartbeats: 2,
      );
      s = reduce(s, RemoteConnectionEvent.heartbeatOk);
      expect(s, RemoteConnectionState.initial);
    });

    test('reconnect lifecycle: down → reconnecting → connected', () {
      var s = const RemoteConnectionState(
        status: RemoteConnectionStatus.down,
        missedHeartbeats: 3,
      );
      s = reduce(s, RemoteConnectionEvent.reconnectStarted);
      expect(s.status, RemoteConnectionStatus.reconnecting);
      s = reduce(s, RemoteConnectionEvent.reconnected);
      expect(s, RemoteConnectionState.initial);
    });

    test('reconnect failure → down', () {
      var s = const RemoteConnectionState(
        status: RemoteConnectionStatus.reconnecting,
      );
      s = reduce(s, RemoteConnectionEvent.reconnectFailed);
      expect(s.status, RemoteConnectionStatus.down);
    });

    test('heartbeat timeouts are ignored while reconnecting', () {
      const s = RemoteConnectionState(
        status: RemoteConnectionStatus.reconnecting,
        missedHeartbeats: 1,
      );
      expect(reduce(s, RemoteConnectionEvent.heartbeatTimeout), s);
    });

    test('custom threshold flips down sooner', () {
      var s = RemoteConnectionState.initial;
      s = reduce(s, RemoteConnectionEvent.heartbeatTimeout, max: 1);
      expect(s.status, RemoteConnectionStatus.down);
    });
  });

  group('RemoteConnectionMonitor', () {
    test('emits only on state change and exposes current state', () async {
      final monitor = RemoteConnectionMonitor(maxMissedBeforeDown: 2);
      final seen = <RemoteConnectionStatus>[];
      final sub = monitor.changes.listen((s) => seen.add(s.status));

      monitor.heartbeatOk(); // already connected → no emission
      monitor.heartbeatTimedOut(); // → degraded
      monitor.heartbeatTimedOut(); // → down (threshold 2)
      monitor.reconnectStarted(); // → reconnecting
      monitor.reconnected(); // → connected

      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        RemoteConnectionStatus.degraded,
        RemoteConnectionStatus.down,
        RemoteConnectionStatus.reconnecting,
        RemoteConnectionStatus.connected,
      ]);
      expect(monitor.state, RemoteConnectionState.initial);
      await sub.cancel();
      await monitor.dispose();
    });

    test('drop isolation: each target has an independent monitor', () async {
      final a = RemoteConnectionMonitor();
      final b = RemoteConnectionMonitor();
      a.markDown();
      expect(a.state.status, RemoteConnectionStatus.down);
      expect(b.state.status, RemoteConnectionStatus.connected);
      await a.dispose();
      await b.dispose();
    });
  });
}
