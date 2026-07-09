import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';

/// Flattens template [DiscoverableTeam.roster] expert keys for Expert Hub
/// "from teams" discovery. Skips built-in catalog keys (already listed).
List<DiscoverableMember> indexMembersFromTeams(List<DiscoverableTeam> teams) {
  const builtinPrefix = 'teampilot/builtin/';
  final indexed = <DiscoverableMember>[];
  final seen = <String>{};
  for (final team in teams) {
    for (final slot in team.roster) {
      final key = slot.expertKey.trim();
      if (key.isEmpty || key.startsWith(builtinPrefix) || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      indexed.add(
        DiscoverableMember(
          key: key,
          name: slot.id,
          description: team.description,
          category: team.category,
          source: ExpertMemberSource.teamExtract,
          originTeamKey: team.key,
          member: DiscoverableTeamMember(name: slot.id),
        ),
      );
    }
  }
  return indexed;
}
