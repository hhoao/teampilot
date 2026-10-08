import 'dispatcher.dart';
import 'event_transport_codec.dart';
import 'session_lifecycle_event.dart';

final class SessionLifecycleTransportCodec
    implements EventTransportFamilyCodec {
  @override
  String get family => eventTransportFamilySessionLifecycle;

  @override
  Map<String, Object?> encode(DispatcherEvent event) {
    final e = event as SessionLifecycleEvent;
    return {
      'kind': e.eventKind.name,
      'sessionId': e.sessionId,
      'workspaceId': e.workspaceId,
      if (e.memberId != null) 'memberId': e.memberId,
      'ts': e.timestamp.toUtc().toIso8601String(),
    };
  }

  @override
  DispatcherEvent? decode(Map<String, Object?> payload) {
    final sessionId = payload['sessionId'] as String?;
    final workspaceId = payload['workspaceId'] as String?;
    final ts = DateTime.tryParse(payload['ts'] as String? ?? '');
    if (sessionId == null || workspaceId == null || ts == null) return null;
    final memberId = payload['memberId'] as String?;
    final utc = ts.toUtc();
    return switch (payload['kind'] as String?) {
      'sessionSpawned' => SessionLifecycleEvent.sessionSpawned(
        sessionId: sessionId,
        workspaceId: workspaceId,
        timestamp: utc,
      ),
      'sessionStarted' => SessionLifecycleEvent.sessionStarted(
        sessionId: sessionId,
        workspaceId: workspaceId,
        timestamp: utc,
      ),
      'sessionClosed' => SessionLifecycleEvent.sessionClosed(
        sessionId: sessionId,
        workspaceId: workspaceId,
        timestamp: utc,
      ),
      'seatStarted' when memberId != null => SessionLifecycleEvent.seatStarted(
        sessionId: sessionId,
        workspaceId: workspaceId,
        memberId: memberId,
        timestamp: utc,
      ),
      'seatInterrupted' when memberId != null =>
        SessionLifecycleEvent.seatInterrupted(
          sessionId: sessionId,
          workspaceId: workspaceId,
          memberId: memberId,
          timestamp: utc,
        ),
      'seatExited' when memberId != null => SessionLifecycleEvent.seatExited(
        sessionId: sessionId,
        workspaceId: workspaceId,
        memberId: memberId,
        timestamp: utc,
      ),
      _ => null,
    };
  }
}
