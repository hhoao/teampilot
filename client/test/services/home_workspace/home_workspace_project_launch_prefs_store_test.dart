import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/home_workspace/home_workspace_project_launch_prefs_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('round-trips per-project launch prefs', () async {
    final tmp = await Directory.systemTemp.createTemp('launch_prefs_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = HomeWorkspaceProjectLaunchPrefsStore(
      fs: LocalFilesystem(),
      pathOverride: '${tmp.path}/launch-prefs.json',
    );

    expect(await store.prefsFor('p1'), isNull);

    await store.save('p1', const ProjectLaunchPref(
      lastIdentity: 'team:abc',
      remember: true,
    ));
    final loaded = await store.prefsFor('p1');
    expect(loaded?.lastIdentity, 'team:abc');
    expect(loaded?.remember, isTrue);

    // Unrelated project unaffected.
    expect(await store.prefsFor('p2'), isNull);
  });
}
