import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../models/app_session.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/terminal/session_member_cli_resolver.dart';
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

  // Prefer selectedMemberId as instance id (e.g. builder-0) so bindingFor
  // hits the replica lock — never rewrite to lead when the selection is a
  // numbered instance that is absent from team.members type ids.
  final selectedId = tab.selectedMemberId.trim();
  if (selectedId.isNotEmpty) {
    return SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: team,
      memberId: selectedId,
      globalPresets: globalPresets,
      cliForMember: (t, id, {List<CliPreset> globalPresets = const []}) {
        final typeMember = _typeMemberForInstance(t, session, id);
        if (typeMember != null) {
          return memberLaunchCli(
            team: t,
            member: typeMember,
            globalPresets: globalPresets,
          );
        }
        return t.cli;
      },
    );
  }

  final member = _leadMember(team);
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

TeamMemberConfig _leadMember(TeamProfile team) {
  for (final m in team.members) {
    if (TeamMemberNaming.isTeamLeadName(m.id)) return m;
  }
  return team.members.first;
}

/// Live type config for [memberId] (type id or replica instance id).
TeamMemberConfig? _typeMemberForInstance(
  TeamProfile team,
  AppSession? session,
  String memberId,
) {
  for (final m in team.members) {
    if (m.id == memberId) return m;
  }
  final typeId = session?.bindingFor(memberId)?.typeId.trim() ?? '';
  if (typeId.isNotEmpty) {
    for (final m in team.members) {
      if (m.id == typeId) return m;
    }
  }
  final dash = memberId.lastIndexOf('-');
  if (dash > 0) {
    final suffix = memberId.substring(dash + 1);
    if (int.tryParse(suffix) != null) {
      final inferred = memberId.substring(0, dash);
      for (final m in team.members) {
        if (m.id == inferred) return m;
      }
    }
  }
  return null;
}
