import '../../models/team_config.dart';
import 'agent_attention_state.dart';

class _SeatRecord {
  const _SeatRecord({required this.cli, required this.skipPermissions});

  final CliTool cli;
  final bool skipPermissions;
}

/// In-memory map of connect-time seat CLI + skip-permissions for status hooks.
///
/// Populated at PTY connect (Task 7); empty until then — unknown seats resolve
/// to null CLI / false skip so `/agent-status` stays a no-op (HTTP 200 `{}`).
class AgentStatusSeatLookup {
  final Map<String, _SeatRecord> _seats = {};

  void registerSeat({
    required String sessionId,
    required String memberId,
    required CliTool cli,
    required bool skipPermissions,
  }) {
    final key = agentSeatKey(sessionId: sessionId, memberId: memberId);
    _seats[key] = _SeatRecord(cli: cli, skipPermissions: skipPermissions);
  }

  void unregisterSeat({required String sessionId, required String memberId}) {
    _seats.remove(agentSeatKey(sessionId: sessionId, memberId: memberId));
  }

  void clearSession(String sessionId) {
    final prefix = '${sessionId.trim()}\u0000';
    _seats.removeWhere((k, _) => k.startsWith(prefix));
  }

  CliTool? resolveCli(String sessionId, String memberId) =>
      _seats[agentSeatKey(sessionId: sessionId, memberId: memberId)]?.cli;

  bool resolveSkipPermissions(String sessionId, String memberId) =>
      _seats[agentSeatKey(sessionId: sessionId, memberId: memberId)]
          ?.skipPermissions ??
      false;
}
