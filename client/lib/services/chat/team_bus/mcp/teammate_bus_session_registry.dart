import 'dart:math';

import 'teammate_bus_mcp_handler.dart';

class TeammateBusSessionRegistration {
  TeammateBusSessionRegistration({
    required this.sessionId,
    required this.handler,
    required this.token,
  });

  final String sessionId;
  final TeammateBusMcpHandler handler;
  final String token;
}

class TeammateBusSessionRegistry {
  final _bySession = <String, TeammateBusSessionRegistration>{};
  final _tokenToSession = <String, String>{};

  TeammateBusSessionRegistration register({
    required String sessionId,
    required TeammateBusMcpHandler handler,
  }) {
    unregister(sessionId);
    final token = _randomToken();
    final reg = TeammateBusSessionRegistration(
      sessionId: sessionId,
      handler: handler,
      token: token,
    );
    _bySession[sessionId] = reg;
    _tokenToSession[token] = sessionId;
    return reg;
  }

  void unregister(String sessionId) {
    final existing = _bySession.remove(sessionId);
    if (existing != null) {
      _tokenToSession.remove(existing.token);
    }
  }

  TeammateBusMcpHandler? handlerForSession(String sessionId) =>
      _bySession[sessionId]?.handler;

  String? sessionForToken(String token) => _tokenToSession[token];

  TeammateBusSessionRegistration? registrationForSession(String sessionId) =>
      _bySession[sessionId];

  Iterable<TeammateBusSessionRegistration> get registrations =>
      _bySession.values;
}

String _randomToken() {
  final rng = Random.secure();
  return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
}
