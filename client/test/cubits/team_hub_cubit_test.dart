import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

class _FakeSource implements TeamHubSource {
  _FakeSource(this.teams);
  final List<DiscoverableTeam> teams;
  int fetchCount = 0;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async {
    fetchCount++;
    return teams;
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      teams.map((t) => t.category).toSet().toList()..sort();
}

DiscoverableTeam _t(String name, String cat, int updated) => DiscoverableTeam(
  key: 'o/r/${name.toLowerCase()}',
  name: name,
  description: 'desc of $name',
  category: cat,
  updatedAt: updated,
);

void main() {
  late _FakeSource source;
  late TeamHubCubit cubit;

  setUp(() {
    source = _FakeSource([
      _t('Beta', 'AI', 30),
      _t('Alpha', 'AI', 10),
      _t('Gamma', 'Testing', 20),
    ]);
    cubit = TeamHubCubit(
      source: source,
      loadFavorites: () async => {'o/r/alpha'},
      saveFavoriteToggle: (key) async => true,
      cloneTeam: (team) async => const CloneResult(
        teamId: 'new-id',
        installed: CloneDepInstallSummary(),
        failedDeps: [],
      ),
    );
  });

  test('load populates teams + categories + favorites', () async {
    await cubit.load();
    expect(cubit.state.allTeams, hasLength(3));
    expect(cubit.state.categories, ['AI', 'Testing']);
    expect(cubit.state.favorites, {'o/r/alpha'});
    expect(cubit.state.status, TeamHubLoadStatus.ready);
  });

  test('category filter narrows visible teams', () async {
    await cubit.load();
    cubit.setCategory('Testing');
    expect(cubit.visibleTeams.map((t) => t.name), ['Gamma']);
    cubit.setCategory(null);
    expect(cubit.visibleTeams, hasLength(3));
  });

  test('search filters by name and description', () async {
    await cubit.load();
    cubit.setSearch('alpha');
    expect(cubit.visibleTeams.map((t) => t.name), ['Alpha']);
  });

  test('sort by name (default) and by time', () async {
    await cubit.load();
    expect(cubit.visibleTeams.map((t) => t.name), ['Alpha', 'Beta', 'Gamma']);
    cubit.setSort(TeamSort.updated);
    expect(cubit.visibleTeams.map((t) => t.name), ['Beta', 'Gamma', 'Alpha']);
  });

  test('favoritesOnly filter narrows to favorite keys', () async {
    await cubit.load();
    cubit.setFavoritesOnly(true);
    expect(cubit.visibleTeams.map((t) => t.name), ['Alpha']);
    cubit.setFavoritesOnly(false);
    expect(cubit.visibleTeams, hasLength(3));
  });

  test('toggleFavorite updates state', () async {
    await cubit.load();
    await cubit.toggleFavorite('o/r/beta');
    expect(cubit.state.favorites.contains('o/r/beta'), isTrue);
  });

  test('clone refreshes installedDepIds', () async {
    var cloneCalls = 0;
    cubit = TeamHubCubit(
      source: source,
      loadFavorites: () async => <String>{},
      saveFavoriteToggle: (key) async => true,
      cloneTeam: (team) async {
        cloneCalls++;
        return const CloneResult(
          teamId: 'new-id',
          installed: CloneDepInstallSummary(skillIds: ['skill-a']),
          failedDeps: [],
        );
      },
      loadInstalledDepIds: () async {
        if (cloneCalls == 0) return const <String>{};
        return const {'skill-a', 'plugin-b'};
      },
    );

    await cubit.clone(_t('Delta', 'AI', 5));
    expect(cloneCalls, 1);
    expect(cubit.state.installedDepIds, {'skill-a', 'plugin-b'});
  });
}
