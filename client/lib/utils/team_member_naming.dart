import '../models/default_team_roster.dart';
import '../models/team_config.dart';

/// Claude team member naming aligned with agentId / inbox / CLI `--agent-name`.
abstract final class TeamMemberNaming {
  static const teamLeadName = 'team-lead';
  static const defaultWorkerName = 'member';

  /// Default roster for a newly created team (leader + developer + reviewer).
  static List<TeamMemberConfig> defaultRoster({int? joinedAt}) =>
      DefaultTeamRoster.bootstrap(joinedAt: joinedAt);

  static bool isTeamLeadName(String raw) => raw.trim() == teamLeadName;

  static bool isTeamLead(TeamMemberConfig member) => isTeamLeadName(member.id);

  /// Strips `@` (invalid in agentId); does not slug spaces.
  static String sanitizeAgentName(String raw) =>
      raw.trim().replaceAll('@', '-');

  static String formatAgentId(String agentName, String teamName) =>
      '${sanitizeAgentName(agentName)}@${teamName.trim()}';

  /// Leader agent id for CLI + roster `leadAgentId`.
  ///
  /// Must stay the bare name `team-lead` (not `team-lead@<team>`) so stock
  /// Claude Code treats this session as leader (`isTeamLeader`, `isTeamLead`)
  /// while still accepting `--agent-id` for inbox polling (`isTeammate`).
  static String leadAgentId(String cliTeamName) => teamLeadName;

  /// `--agent-id` for a member launch ([TeamMemberConfig.id] + [cliTeamName]).
  static String cliAgentId({
    required String memberId,
    required String cliTeamName,
  }) {
    if (memberId.trim() == teamLeadName) {
      return leadAgentId(cliTeamName);
    }
    return formatAgentId(memberId, cliTeamName);
  }

  /// Stable key for [TeamProfile.id], config paths, and `sessionTeam` / `cliTeamName` prefix.
  static String slugTeamId(String raw) {
    var s = sanitizeAgentName(raw);
    s = s.replaceAll(RegExp(r'\s+'), '-');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (s.isEmpty) return 'team';
    return s.toLowerCase();
  }

  /// [slugTeamId] with `-2`, `-3`, … when [existingIds] already contains the base slug.
  static String uniqueTeamId(String displayName, Iterable<String> existingIds) {
    final taken = existingIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final base = slugTeamId(displayName);
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base-$n')) {
      n++;
    }
    return '$base-$n';
  }

  /// Slug for [TeamMemberConfig.id] at create/load (non-lead).
  static String slugMemberName(String raw) {
    if (raw.trim() == teamLeadName) return teamLeadName;
    var s = sanitizeAgentName(raw);
    s = s.replaceAll(RegExp(r'\s+'), '-');
    s = s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (s.isEmpty) return 'member';
    return s.toLowerCase();
  }

  static String? validateMemberName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'empty';
    if (trimmed.contains('@')) return 'at_sign';
    return null;
  }

  static String resolveAgentType({
    required String memberId,
    required String agent,
    required String agentType,
  }) {
    if (memberId == teamLeadName) return teamLeadName;
    final role = agentType.trim();
    if (role.isNotEmpty) return role;
    final fromAgent = agent.trim();
    if (fromAgent.isNotEmpty) return fromAgent;
    return memberId;
  }
}
