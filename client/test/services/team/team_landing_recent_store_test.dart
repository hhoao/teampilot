import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/team_landing_recent_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late TeamLandingRecentStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = AppPaths('/tp');
    store = TeamLandingRecentStore(
      fs: fs,
      pathOverride: paths.teamHubRecentJson,
    );
  });

  test('touch prepends teamId and dedupes', () async {
    await store.touch('team-a');
    await store.touch('team-b');
    expect(await store.loadOrderedKeys(), ['team-b', 'team-a']);
    await store.touch('team-a');
    expect(await store.loadOrderedKeys(), ['team-a', 'team-b']);
  });

  test('touch caps at maxEntries', () async {
    for (var i = 0; i < 12; i++) {
      await store.touch('team-$i');
    }
    final keys = await store.loadOrderedKeys();
    expect(keys.length, TeamLandingRecentStore.maxEntries);
    expect(keys.first, 'team-11');
    expect(keys, isNot(contains('team-0')));
  });
}
