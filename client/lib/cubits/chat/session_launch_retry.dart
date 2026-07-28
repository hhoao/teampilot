import 'package:collection/collection.dart';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';
import 'model/session_connect_request.dart';

/// Rebuilds an [ExistingSessionConnect] for [session], resolving the member
/// (for team sessions) the same way [SessionWorkbenchViewToggle] does:
/// selected member id, else team-lead, else first roster member.
///
/// Returns `null` when [session] belongs to a team but [team] is unavailable.
ExistingSessionConnect? buildRetryExistingSessionConnect({
  required AppSession session,
  required String selectedMemberId,
  TeamProfile? team,
  bool preserveWorkbenchView = true,
}) {
  final isPersonal = session.sessionTeam.trim().isEmpty;
  if (isPersonal) {
    return ExistingSessionConnect(
      session: session,
      preserveWorkbenchView: preserveWorkbenchView,
    );
  }
  if (team == null) return null;

  TeamMemberConfig? member;
  final mid = selectedMemberId.trim();
  if (mid.isNotEmpty) {
    member = team.members.where((m) => m.id == mid).firstOrNull;
  }
  member ??= team.members.where(TeamMemberNaming.isTeamLead).firstOrNull;
  member ??= team.members.firstOrNull;

  return ExistingSessionConnect(
    session: session,
    team: team,
    member: member,
    preserveWorkbenchView: preserveWorkbenchView,
  );
}
