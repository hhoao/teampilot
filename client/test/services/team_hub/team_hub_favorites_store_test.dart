import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_hub/team_hub_favorites_store.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('add/remove/toggle persist across instances', () async {
    final store = TeamHubFavoritesStore();
    expect(await store.load(), isEmpty);

    await store.add('a/b/x');
    await store.add('a/b/y');
    expect(await store.load(), {'a/b/x', 'a/b/y'});

    await store.remove('a/b/x');
    expect(await store.load(), {'a/b/y'});

    final toggledOff = await store.toggle('a/b/y');
    expect(toggledOff, false);
    expect(await store.load(), isEmpty);

    // New instance reads the same persisted file.
    final fresh = TeamHubFavoritesStore();
    await fresh.add('a/b/z');
    expect(await TeamHubFavoritesStore().load(), {'a/b/z'});
  });
}
