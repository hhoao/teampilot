import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';

class _FakeSource implements ExpertHubSource {
  int fetchCount = 0;

  /// Each fetch returns the entry at [fetchCount] (last one repeats), so tests
  /// can observe fresh data after a refetch.
  _FakeSource(this.versions);

  final List<List<DiscoverableMember>> versions;

  _FakeSource.single()
    : versions = [
        [
          DiscoverableMember.fromJson({
            'key': 'teampilot/builtin/pm',
            'name': 'PM',
          }),
        ],
      ];

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    final index = fetchCount < versions.length ? fetchCount : versions.length - 1;
    fetchCount++;
    return versions[index];
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => [];
}

void main() {
  test('snapshot() is single-flight: concurrent callers fetch once', () async {
    final source = _FakeSource.single();
    final catalog = ExpertHubCatalog(source: source);
    final a = catalog.snapshot();
    final b = catalog.snapshot();
    expect(identical(await a, await b), isTrue);
    expect(source.fetchCount, 1);
  });

  test('invalidate() forces the next snapshot() to refetch', () async {
    final source = _FakeSource.single();
    final catalog = ExpertHubCatalog(source: source);
    await catalog.snapshot();
    catalog.invalidate();
    await catalog.snapshot();
    expect(source.fetchCount, 2);
  });

  test('refresh() returns fresh data and refetches after a prior snapshot', () async {
    final source = _FakeSource([
      [
        DiscoverableMember.fromJson({
          'key': 'teampilot/builtin/pm',
          'name': 'PM',
        }),
      ],
      [
        DiscoverableMember.fromJson({
          'key': 'teampilot/builtin/dev',
          'name': 'Dev',
        }),
      ],
    ]);
    final catalog = ExpertHubCatalog(source: source);
    await catalog.snapshot();

    final refreshed = await catalog.refresh();
    expect(source.fetchCount, 2);
    expect(refreshed.lookup('teampilot/builtin/dev')?.name, 'Dev');
    expect(refreshed.lookup('teampilot/builtin/pm'), isNull);
    // The refreshed snapshot is also what subsequent snapshot() callers see.
    expect(identical(await catalog.snapshot(), refreshed), isTrue);
    expect(source.fetchCount, 2);
  });

  test('snapshot map is unmodifiable', () async {
    final catalog = ExpertHubCatalog(source: _FakeSource.single());
    final snap = await catalog.snapshot();
    expect(
      () => snap.byKey['teampilot/builtin/x'] =
          snap.byKey['teampilot/builtin/pm']!,
      throwsUnsupportedError,
    );
  });

  test('lookup trims and hits by key', () async {
    final catalog = ExpertHubCatalog(source: _FakeSource.single());
    final snap = await catalog.snapshot();
    expect(snap.lookup(' teampilot/builtin/pm ')?.name, 'PM');
    expect(snap.lookup('missing'), isNull);
  });
}
