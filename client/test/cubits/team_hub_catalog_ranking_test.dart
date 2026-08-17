import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

class _Source implements TeamHubSource, TeamHubSourceContributions {
  _Source(this.results);

  List<CatalogSourceResult<DiscoverableTeam>> results;
  Completer<List<CatalogSourceResult<DiscoverableTeam>>>? pending;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({
    bool forceRefresh = false,
  }) async => results.expand((result) => result.items).toList();

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => results
      .expand((result) => result.items)
      .map((t) => t.category)
      .toSet()
      .toList();

  @override
  Future<List<CatalogSourceResult<DiscoverableTeam>>> fetchTeamSources({
    bool forceRefresh = false,
  }) async {
    final wait = pending;
    if (wait != null) return wait.future;
    return results;
  }
}

DiscoverableTeam _team(
  String name, {
  int? adoption,
  int? updated,
  int? published,
}) => DiscoverableTeam(
  key: 'o/r/${name.toLowerCase()}',
  name: name,
  description: 'desc',
  category: 'AI',
  updatedAt: updated ?? 0,
  metrics: CatalogMetrics(
    adoptionCount: adoption,
    updatedAtMs: updated,
    publishedAtMs: published,
  ),
);

TeamHubCubit _cubit(TeamHubSource source) => TeamHubCubit(
  source: source,
  loadFavorites: () async => const <String>{},
  saveFavoriteToggle: (_) async => true,
  cloneTeam: (team, {teamMode, cli}) async => const CloneResult(
    teamId: 'clone',
    installed: CloneDepInstallSummary(),
    failedDeps: [],
  ),
);

void main() {
  test(
    'sorts teams by adoption with nulls last and stable tie-breaks',
    () async {
      final cubit = _cubit(
        _Source([
          CatalogSourceResult(
            sourceId: 'registry',
            sourceLabel: 'Registry',
            items: [
              _team('Zulu', adoption: 10, updated: 10),
              _team('Alpha', adoption: 10, updated: 20),
              _team('Beta', adoption: null, updated: 100),
              _team('Gamma', adoption: 10, updated: 20),
            ],
          ),
        ]),
      );

      await cubit.load();

      expect(cubit.state.sort, CatalogSortKey.adoption);
      expect(cubit.visibleTeams.map((team) => team.name), [
        'Alpha',
        'Gamma',
        'Zulu',
        'Beta',
      ]);

      cubit.setSort(CatalogSortKey.published);
      expect(cubit.visibleTeams.map((team) => team.name), [
        'Beta',
        'Alpha',
        'Gamma',
        'Zulu',
      ]);
    },
  );

  test('keeps successful source results and exposes safe failures', () async {
    final cubit = _cubit(
      _Source([
        CatalogSourceResult(
          sourceId: 'builtin',
          sourceLabel: 'Built-in',
          items: [_team('Local Team', adoption: null)],
        ),
        CatalogSourceResult(
          sourceId: 'registry',
          sourceLabel: 'Public registry',
          items: const [],
          failure: const CatalogSourceFailure(
            sourceId: 'registry',
            sourceLabel: 'Public registry',
            message: 'request timed out',
          ),
        ),
      ]),
    );

    await cubit.load();

    expect(cubit.state.allTeams.map((team) => team.name), ['Local Team']);
    expect(cubit.state.sourceFailures, hasLength(1));
    expect(cubit.state.sourceFailures.single.sourceId, 'registry');
    expect(cubit.state.status, TeamHubLoadStatus.ready);
    expect(cubit.state.errorMessage, isNull);
  });

  test('retains existing teams while a refresh is pending', () async {
    final source = _Source([
      CatalogSourceResult(
        sourceId: 'registry',
        sourceLabel: 'Registry',
        items: [_team('Old Team', adoption: 1)],
      ),
    ]);
    final cubit = _cubit(source);
    await cubit.load();

    final pending = Completer<List<CatalogSourceResult<DiscoverableTeam>>>();
    source.pending = pending;
    final refresh = cubit.load(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.allTeams.map((team) => team.name), ['Old Team']);
    expect(cubit.state.refreshing, isTrue);

    pending.complete([
      CatalogSourceResult(
        sourceId: 'registry',
        sourceLabel: 'Registry',
        items: [_team('New Team', adoption: 2)],
      ),
    ]);
    await refresh;
    expect(cubit.state.allTeams.map((team) => team.name), ['New Team']);
  });

  test('is blocking only when every source failed without results', () async {
    final cubit = _cubit(
      _Source([
        CatalogSourceResult<DiscoverableTeam>(
          sourceId: 'registry',
          sourceLabel: 'Public registry',
          items: const [],
          failure: const CatalogSourceFailure(
            sourceId: 'registry',
            sourceLabel: 'Public registry',
            message: 'unavailable',
          ),
        ),
      ]),
    );

    await cubit.load();

    expect(cubit.state.status, TeamHubLoadStatus.error);
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.sourceFailures, hasLength(1));
  });
}
