import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';

class _FakeSource implements ExpertHubSource {
  int fetchCount = 0;
  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    fetchCount++;
    return [
      DiscoverableMember.fromJson({
        'key': 'teampilot/builtin/pm',
        'name': 'PM',
      }),
    ];
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => [];
}

void main() {
  test('snapshot() is single-flight: concurrent callers fetch once', () async {
    final source = _FakeSource();
    final catalog = ExpertHubCatalog(source: source);
    final a = catalog.snapshot();
    final b = catalog.snapshot();
    expect(identical(await a, await b), isTrue);
    expect(source.fetchCount, 1);
  });

  test('invalidate() forces the next snapshot() to refetch', () async {
    final source = _FakeSource();
    final catalog = ExpertHubCatalog(source: source);
    await catalog.snapshot();
    catalog.invalidate();
    await catalog.snapshot();
    expect(source.fetchCount, 2);
  });

  test('lookup trims and hits by key', () async {
    final catalog = ExpertHubCatalog(source: _FakeSource());
    final snap = await catalog.snapshot();
    expect(snap.lookup(' teampilot/builtin/pm ')?.name, 'PM');
    expect(snap.lookup('missing'), isNull);
  });
}
