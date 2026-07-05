import '../../models/discoverable_member.dart';
import '../../models/discoverable_team.dart';
import '../../utils/team_member_naming.dart';

/// Denormalizes [DiscoverableTeam.members] into standalone [DiscoverableMember]
/// entries for Expert Hub discovery.
List<DiscoverableMember> indexMembersFromTeams(List<DiscoverableTeam> teams) {
  final indexed = <DiscoverableMember>[];
  for (final team in teams) {
    for (final member in team.members) {
      final slug = TeamMemberNaming.slugMemberName(member.name);
      indexed.add(
        DiscoverableMember(
          key: '${team.key}#$slug',
          name: member.name.trim().isNotEmpty ? member.name.trim() : slug,
          description: team.description,
          category: team.category,
          source: ExpertMemberSource.teamExtract,
          originTeamKey: team.key,
          member: member,
          skillDeps: team.skillDeps,
        ),
      );
    }
  }
  return indexed;
}
