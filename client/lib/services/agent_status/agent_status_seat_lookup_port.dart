import '../../models/team_config.dart';

/// Connect-time seat CLI + skip-permissions writes used at launch dispose.
abstract interface class AgentStatusSeatLookupPort {
  void registerSeat({
    required String sessionId,
    required String memberId,
    required CliTool cli,
    required bool skipPermissions,
  });

  void unregisterSeat({required String sessionId, required String memberId});

  void clearSession(String sessionId);
}
