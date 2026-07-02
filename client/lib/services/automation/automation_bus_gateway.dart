import '../../cubits/chat/tab_team_bus_coordinator.dart';

/// Delivery seam for automation dispatch (TeamBus / PTY inject path).
abstract interface class AutomationBusGateway {
  void deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  );

  Future<void> ensureMemberReady(String sessionId, String memberId);
}

class TabTeamBusGateway implements AutomationBusGateway {
  TabTeamBusGateway(this._coordinator);

  final TabTeamBusCoordinator _coordinator;

  @override
  void deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) {
    _coordinator.deliverUserCommandToMember(sessionId, memberId, message);
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) {
    return _coordinator.materializeMember(sessionId, memberId, '');
  }
}
