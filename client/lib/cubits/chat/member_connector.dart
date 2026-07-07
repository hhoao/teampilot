import '../../models/team_config.dart';
import 'model/chat_tab.dart';

/// Edge ChatCubit must implement so member materialization can drive connects.
abstract interface class MemberConnector {
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    ChatTab tab,
  );
}
