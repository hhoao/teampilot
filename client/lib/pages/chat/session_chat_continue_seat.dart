import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';

/// Resolves the Chat continue / PTY-or-mailbox delivery seat for [selectedMemberId].
///
/// Prefers session runtime pods ([sessionRosterMembers]) so numbered instance
/// ids (`developer-0`) match the Members panel. Falls back to
/// [runtimeRosterMembers] when the session has no bindings yet.
///
/// Returns null when a non-empty selection cannot be resolved — callers must
/// not silently retarget to the team lead.
TeamMemberConfig? resolveSessionChatContinueMember({
  required AppSession session,
  required TeamProfile team,
  required String selectedMemberId,
}) {
  final mid = selectedMemberId.trim();
  final roster = session.members.isNotEmpty
      ? sessionRosterMembers(session, team)
      : runtimeRosterMembers(team);

  if (mid.isNotEmpty) {
    for (final member in roster) {
      if (member.id == mid) return member;
    }
    for (final member in team.members) {
      if (member.id == mid) return member;
    }
    return null;
  }

  return team.members.where(TeamMemberNaming.isTeamLead).firstOrNull ??
      team.members.firstOrNull ??
      roster.firstOrNull;
}
