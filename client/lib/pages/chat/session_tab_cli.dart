import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../models/app_session.dart';
import '../../services/cli/preset_resolver.dart';
import '../../utils/team/team_member_naming.dart';

/// CLI brand shown on a workspace session tab.
CliTool resolveSessionTabCli({
  required ChatTab tab,
  required List<AppSession> sessions,
  required bool isPersonal,
  TeamProfile? team,
  CliTool? personalFallbackCli,
  List<CliPreset> globalPresets = const [],
}) {
  final session = _sessionForTab(tab, sessions);

  // Simple / personal: pin from AppSession.cli. Team tabs must not prefer
  // session.cli — that field is Simple-only; use binding lock via resolver.
  if (isPersonal) {
    return session?.cli ?? personalFallbackCli ?? CliTool.claude;
  }
  if (team == null) return CliTool.claude;

  final member = _memberForTab(tab, team);
  return sessionMemberLaunchCli(
    session: session,
    team: team,
    member: member,
    globalPresets: globalPresets,
  );
}

AppSession? _sessionForTab(ChatTab tab, List<AppSession> sessions) {
  final cached = tab.persistedSession;
  if (cached != null) return cached;
  final tabId = tab.info.id;
  if (tabId.startsWith('local-')) return null;
  for (final s in sessions) {
    if (s.sessionId == tabId) return s;
  }
  return null;
}

TeamMemberConfig _memberForTab(ChatTab tab, TeamProfile team) {
  final memberId = tab.selectedMemberId.trim();
  if (memberId.isNotEmpty) {
    for (final m in team.members) {
      if (m.id == memberId) return m;
    }
  }
  for (final m in team.members) {
    if (TeamMemberNaming.isTeamLeadName(m.id)) return m;
  }
  return team.members.first;
}
