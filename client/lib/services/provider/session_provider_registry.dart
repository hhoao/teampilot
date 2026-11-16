/// Tracks which provider id each live session was launched with.
///
/// The lease endpoint uses this to reject requests whose `providerId` does not
/// match the seat that owns the shim, and to reject unknown sessions. Entries
/// are written by the credential adapter at launch time, so every seat —
/// including Simple/native sessions that never register with the TeamBus
/// gateway — is covered without depending on the gateway's construction order.
final class SessionProviderRegistry {
  final Map<String, String> _bySession = <String, String>{};

  /// Records the provider a session was materialized with.
  void register(String sessionId, String providerId) {
    if (sessionId.trim().isEmpty || providerId.trim().isEmpty) return;
    _bySession[sessionId] = providerId;
  }

  /// Drops a session once it is gone. Optional: entries are process-local and
  /// only live as long as the seat does.
  void unregister(String sessionId) => _bySession.remove(sessionId);

  /// Resolves the provider a session may request credentials for. Returns
  /// null for an unknown session, which the endpoint maps to 401.
  String? providerFor(String sessionId) => _bySession[sessionId];
}
