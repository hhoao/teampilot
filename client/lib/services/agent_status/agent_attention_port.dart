import 'agent_status_event.dart';

/// Seat attention writes used at launch and by terminal observation.
abstract interface class AgentAttentionPort {
  void applyEvent({
    required String sessionId,
    required String memberId,
    required AgentStatusEvent event,
    required bool skipPermissions,
  });

  void clearSeat({required String sessionId, required String memberId});

  void clearSession(String sessionId);
}
