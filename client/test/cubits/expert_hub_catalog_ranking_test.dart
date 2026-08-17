import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import '../support/stub_member_roster_service.dart';

class _Registry implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) =>
      Future.value(const []);

  @override
  Future<List<String>> categories({bool forceRefresh = false}) =>
      Future.value(const []);
}

class _Source extends CompositeExpertHubSource {
  _Source(this.results) : super(builtIns: const [], registry: _Registry());

  List<CatalogSourceResult<DiscoverableMember>> results;
  Completer<List<CatalogSourceResult<DiscoverableMember>>>? pending;

  @override
  Future<List<CatalogSourceResult<DiscoverableMember>>> fetchMemberSources({
    bool forceRefresh = false,
  }) async {
    final wait = pending;
    if (wait != null) return wait.future;
    return results;
  }
}

DiscoverableMember _member(
  String name, {
  int? adoption,
  int? updated,
  int? published,
}) => DiscoverableMember(
  key: 'o/r/${name.toLowerCase()}',
  name: name,
  description: 'desc',
  category: 'AI',
  source: ExpertMemberSource.registry,
  updatedAt: updated ?? 0,
  member: DiscoverableTeamMember(name: name.toLowerCase()),
  metrics: CatalogMetrics(
    adoptionCount: adoption,
    updatedAtMs: updated,
    publishedAtMs: published,
  ),
);

ExpertHubCubit _cubit(CompositeExpertHubSource source) => ExpertHubCubit(
  source: source,
  loadFavorites: () async => const <String>{},
  saveFavoriteToggle: (_) async => true,
  memberRosterService: stubMemberRosterService(),
  launchProfiles: () => throw UnimplementedError('not used'),
);

void main() {
  test('sorts experts by adoption independently with nulls last', () async {
    final cubit = _cubit(
      _Source([
        CatalogSourceResult(
          sourceId: 'registry',
          sourceLabel: 'Registry',
          items: [
            _member('Zulu', adoption: 10, updated: 10),
            _member('Alpha', adoption: 10, updated: 20),
            _member('Beta', adoption: null, updated: 100),
            _member('Gamma', adoption: 10, updated: 20),
          ],
        ),
      ]),
    );

    await cubit.load();

    expect(cubit.state.sort, CatalogSortKey.adoption);
    expect(cubit.visibleMembers().map((member) => member.name), [
      'Alpha',
      'Gamma',
      'Zulu',
      'Beta',
    ]);
    cubit.setSort(CatalogSortKey.rating);
    expect(cubit.visibleMembers().map((member) => member.name), [
      'Beta',
      'Alpha',
      'Gamma',
      'Zulu',
    ]);
  });

  test('keeps successful expert sources and records failures', () async {
    final cubit = _cubit(
      _Source([
        CatalogSourceResult(
          sourceId: 'builtin',
          sourceLabel: 'Built-in',
          items: [_member('Local Expert')],
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

    expect(cubit.state.allMembers.map((member) => member.name), [
      'Local Expert',
    ]);
    expect(cubit.state.sourceFailures.single.sourceId, 'registry');
    expect(cubit.state.status, ExpertHubLoadStatus.ready);
    expect(cubit.state.errorMessage, isNull);
  });

  test('retains existing experts while refresh is pending', () async {
    final source = _Source([
      CatalogSourceResult(
        sourceId: 'registry',
        sourceLabel: 'Registry',
        items: [_member('Old Expert', adoption: 1)],
      ),
    ]);
    final cubit = _cubit(source);
    await cubit.load();

    final pending = Completer<List<CatalogSourceResult<DiscoverableMember>>>();
    source.pending = pending;
    final refresh = cubit.load(forceRefresh: true);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.allMembers.map((member) => member.name), ['Old Expert']);
    expect(cubit.state.refreshing, isTrue);

    pending.complete([
      CatalogSourceResult(
        sourceId: 'registry',
        sourceLabel: 'Registry',
        items: [_member('New Expert', adoption: 2)],
      ),
    ]);
    await refresh;
    expect(cubit.state.allMembers.map((member) => member.name), ['New Expert']);
  });
}
