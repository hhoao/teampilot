import '../../models/discoverable_team.dart';
import '../../models/team_config.dart';
import '../../services/team/team_landing_selection.dart';

enum TeamLandingSourceFilter { all, mine, discovery }

sealed class TeamLandingEntry {
  String get name;
  String get description;
}

class TeamLandingLocalEntry extends TeamLandingEntry {
  TeamLandingLocalEntry(this.team);

  final TeamProfile team;

  @override
  String get name => team.name;

  @override
  String get description => team.description;
}

class TeamLandingHubEntry extends TeamLandingEntry {
  TeamLandingHubEntry(this.team, {this.localTeamId});

  final DiscoverableTeam team;
  final String? localTeamId;

  @override
  String get name => team.name;

  @override
  String get description => team.description;
}

class TeamLandingCatalogSections {
  const TeamLandingCatalogSections({
    required this.mine,
    required this.discovery,
  });

  final List<TeamLandingLocalEntry> mine;
  final List<TeamLandingHubEntry> discovery;
}

bool _matchesSearch(String name, String description, String searchQuery) {
  final query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  return name.toLowerCase().contains(query) ||
      description.toLowerCase().contains(query);
}

TeamLandingCatalogSections buildTeamLandingCatalog({
  required List<TeamProfile> localTeams,
  required List<DiscoverableTeam> hubTeams,
  required TeamLandingSourceFilter sourceFilter,
  required String searchQuery,
  required bool favoritesOnly,
  required Set<String> favoriteKeys,
  String? category,
}) {
  final mine = sourceFilter == TeamLandingSourceFilter.discovery
      ? const <TeamLandingLocalEntry>[]
      : localTeams
            .where(
              (team) => _matchesSearch(team.name, team.description, searchQuery),
            )
            .map(TeamLandingLocalEntry.new)
            .toList(growable: false);

  final discovery = sourceFilter == TeamLandingSourceFilter.mine
      ? const <TeamLandingHubEntry>[]
      : hubTeams
            .where((team) {
              if (favoritesOnly && !favoriteKeys.contains(team.key)) {
                return false;
              }
              if (category != null && team.category != category) {
                return false;
              }
              return _matchesSearch(team.name, team.description, searchQuery);
            })
            .map((team) {
              final local = earliestTeamWithHubSourceKey(localTeams, team.key);
              return TeamLandingHubEntry(team, localTeamId: local?.id);
            })
            .toList(growable: false);

  return TeamLandingCatalogSections(mine: mine, discovery: discovery);
}
