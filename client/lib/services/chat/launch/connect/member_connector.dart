import '../../../../models/team_config.dart';

/// Edge ChatCubit must implement so member materialization can drive connects.
abstract interface class MemberConnector {
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    String sessionId, {
    bool selectMember = true,
  });
}
