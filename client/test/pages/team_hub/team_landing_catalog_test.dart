import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/team_hub/team_landing_catalog.dart';

DiscoverableTeam hub({
  required String key,
  String name = 'Hub',
  String description = '',
  String category = 'general',
}) => DiscoverableTeam(
  key: key,
  name: name,
  description: description,
  category: category,
  updatedAt: 1,
);

TeamLandingCatalogSections catalog({
  List<TeamProfile> localTeams = const [],
  List<DiscoverableTeam> hubTeams = const [],
  TeamLandingSourceFilter sourceFilter = TeamLandingSourceFilter.all,
  String searchQuery = '',
  bool favoritesOnly = false,
  Set<String> favoriteKeys = const {},
  String? category,
}) => buildTeamLandingCatalog(
  localTeams: localTeams,
  hubTeams: hubTeams,
  sourceFilter: sourceFilter,
  searchQuery: searchQuery,
  favoritesOnly: favoritesOnly,
  favoriteKeys: favoriteKeys,
  category: category,
);

void main() {
  group('buildTeamLandingCatalog', () {
    test('maps hub localTeamId via earliest hubSourceKey match', () {
      final sections = catalog(
        localTeams: const [
          TeamProfile(
            id: 'newer',
            name: 'Newer',
            hubSourceKey: 'o/r/s',
            createdAt: 200,
          ),
          TeamProfile(
            id: 'older',
            name: 'Older',
            hubSourceKey: 'o/r/s',
            createdAt: 100,
          ),
        ],
        hubTeams: [hub(key: 'o/r/s')],
      );

      expect(sections.discovery, hasLength(1));
      expect(sections.discovery.single.localTeamId, 'older');
    });

    test('search matches name and description case-insensitively', () {
      final sections = catalog(
        localTeams: const [
          TeamProfile(id: 'l1', name: 'Alpha Local', description: 'zzz'),
          TeamProfile(id: 'l2', name: 'Beta', description: 'needle'),
        ],
        hubTeams: [
          hub(key: 'h1', name: 'Gamma Hub', description: ''),
          hub(key: 'h2', name: 'Delta', description: 'NEEDLE too'),
        ],
        searchQuery: 'needle',
      );

      expect(sections.mine.map((e) => e.team.id), ['l2']);
      expect(sections.discovery.map((e) => e.team.key), ['h2']);
    });

    test('mine source filter hides discovery rows', () {
      final sections = catalog(
        localTeams: const [TeamProfile(id: 'l1', name: 'Mine')],
        hubTeams: [hub(key: 'h1')],
        sourceFilter: TeamLandingSourceFilter.mine,
      );

      expect(sections.mine, hasLength(1));
      expect(sections.discovery, isEmpty);
    });

    test('discovery favoritesOnly filters hub rows only', () {
      final sections = catalog(
        localTeams: const [TeamProfile(id: 'l1', name: 'Mine')],
        hubTeams: [
          hub(key: 'fav', name: 'Favorite'),
          hub(key: 'other', name: 'Other'),
        ],
        sourceFilter: TeamLandingSourceFilter.discovery,
        favoritesOnly: true,
        favoriteKeys: {'fav'},
      );

      expect(sections.mine, isEmpty);
      expect(sections.discovery.map((e) => e.team.key), ['fav']);
    });

    test('category filter does not drop mine when sourceFilter is all', () {
      final sections = catalog(
        localTeams: const [TeamProfile(id: 'l1', name: 'Local')],
        hubTeams: [
          hub(key: 'g1', category: 'general'),
          hub(key: 'd1', category: 'devops'),
        ],
        sourceFilter: TeamLandingSourceFilter.all,
        category: 'devops',
      );

      expect(sections.mine, hasLength(1));
      expect(sections.discovery.map((e) => e.team.key), ['d1']);
    });
  });
}
