import '../services/team_hub/builtin_team_templates.dart';
import '../utils/team_member_naming.dart';
import 'team_roster_slot.dart';

/// Default roster slots for a newly created team (leader + developer + reviewer).
abstract final class DefaultTeamRoster {
  static const developerMemberId = 'developer';
  static const reviewerMemberId = 'reviewer';

  static String expertKeyForSlug(String slug) =>
      '$kBuiltinTeamHubKeyPrefix/$slug';

  static List<TeamRosterSlot> bootstrap({int? joinedAt}) {
    final ts = joinedAt ?? DateTime.now().millisecondsSinceEpoch;
    return [
      TeamRosterSlot(
        id: TeamMemberNaming.teamLeadName,
        expertKey: expertKeyForSlug('team-lead'),
        joinedAt: ts,
      ),
      TeamRosterSlot(
        id: developerMemberId,
        expertKey: expertKeyForSlug('developer'),
        joinedAt: ts,
      ),
      TeamRosterSlot(
        id: reviewerMemberId,
        expertKey: expertKeyForSlug('reviewer'),
        joinedAt: ts,
      ),
    ];
  }
}
