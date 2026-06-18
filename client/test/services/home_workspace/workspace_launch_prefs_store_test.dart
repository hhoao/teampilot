import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/workspace_launch_prefs_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('round-trips per-workspace launch prefs', () async {
    final tmp = await Directory.systemTemp.createTemp('launch_prefs_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = WorkspaceLaunchPrefsStore(
      fs: LocalFilesystem(),
      pathOverride: '${tmp.path}/launch-prefs.json',
    );

    expect(await store.prefsFor('p1'), isNull);

    await store.save('p1', const WorkspaceLaunchPref(
      lastIdentity: 'team:abc',
      remember: true,
    ));
    final loaded = await store.prefsFor('p1');
    expect(loaded?.lastIdentity, 'team:abc');
    expect(loaded?.remember, isTrue);

    // Unrelated workspace unaffected.
    expect(await store.prefsFor('p2'), isNull);
  });
}
