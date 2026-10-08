import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../session/chat_tab.dart';
import 'bus_user_line_capture.dart';

/// Launch-facing TeamBus seam used at connect: install the mixed-mode bus and
/// intercept PTY input while a member is parked in `wait_for_message`.
abstract interface class TeamBusUserInputPort {
  Future<void> installBusForTab(
    ChatTab tab,
    TeamProfile team,
    AppSession session,
  );

  BusUserInputRouting? busUserInputRouting(
    ChatTab tab,
    TeamProfile team,
    TeamMemberConfig member,
  );
}
