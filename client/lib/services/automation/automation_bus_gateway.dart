import '../../cubits/chat/tab_team_bus_coordinator.dart';

/// Delivery seam for automation dispatch (TeamBus / PTY inject path).
abstract interface class AutomationBusGateway {
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  );

  /// PTY connected and member past startup (TUI frame + agent loop when needed).
  Future<void> ensureMemberReady(String sessionId, String memberId);
}

class TabTeamBusGateway implements AutomationBusGateway {
  TabTeamBusGateway(this._coordinator);

  final TabTeamBusCoordinator _coordinator;

  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) {
    return _coordinator.deliverUserCommandToMember(
      sessionId,
      memberId,
      message,
    );
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) {
    return _coordinator.ensureMemberInputReady(sessionId, memberId);
  }
}
