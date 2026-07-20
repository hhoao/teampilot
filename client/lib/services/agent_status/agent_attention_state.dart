/// Per-seat attention vocabulary for agent status (v1).
enum AgentSeatAttention { working, waiting, done }

/// Stable map key for a session seat (`sessionId` + member instance id).
String agentSeatKey({required String sessionId, required String memberId}) =>
    '${sessionId.trim()}\u0000${memberId.trim()}';
