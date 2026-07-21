import '../../cubits/chat/tab_member_materializer.dart';
import '../../cubits/chat/tab_session_runtime_coordinator.dart';

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
  TabTeamBusGateway({
    required TabMemberMaterializer memberMaterializer,
    required TabSessionRuntimeCoordinator sessionRuntime,
  }) : _memberMaterializer = memberMaterializer,
       _sessionRuntime = sessionRuntime;

  final TabMemberMaterializer _memberMaterializer;
  final TabSessionRuntimeCoordinator _sessionRuntime;

  @override
  Future<void> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message,
  ) async {
    await _sessionRuntime.deliverUserCommandToMember(
      sessionId,
      memberId,
      message,
      directToPty: true,
    );
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) {
    return _memberMaterializer.ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: true,
    );
  }
}
