/// Claude team member naming aligned with agentId / inbox / CLI `--agent-name`.
abstract final class TeamMemberNaming {
  static const teamLeadName = 'team-lead';

  /// Strips `@` (invalid in agentId); does not slug spaces.
  static String sanitizeAgentName(String raw) =>
      raw.trim().replaceAll('@', '-');

  static String formatAgentId(String agentName, String teamName) =>
      '${sanitizeAgentName(agentName)}@${teamName.trim()}';

  /// Slug for roster `name`, inbox paths, and CLI `--agent-name` (non-lead).
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
    required String memberName,
    required String agent,
    required String agentType,
  }) {
    if (memberName == teamLeadName) return teamLeadName;
    final role = agentType.trim();
    if (role.isNotEmpty) return role;
    final fromAgent = agent.trim();
    if (fromAgent.isNotEmpty) return fromAgent;
    return slugMemberName(memberName);
  }
}
