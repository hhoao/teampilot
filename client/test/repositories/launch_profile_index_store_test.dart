import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/index_snapshot_isolate.dart';
import 'package:teampilot/repositories/launch_profile_index_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('launch_profile_index_store_');
  });

  tearDown(() {
    IndexSnapshotIsolate.debugLaunchProfilesReaderOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'upsert completes even when isolate index reader never returns',
    () async {
      IndexSnapshotIsolate.debugLaunchProfilesReaderOverride = (_) =>
          Completer<List<Map<String, Object?>>?>().future;

      final profilesDir = p.join(tmp.path, 'launch-profiles');
      Directory(profilesDir).createSync(recursive: true);
      final store = LaunchProfileIndexStore(
        launchProfilesDir: profilesDir,
        fs: LocalFilesystem(),
      );
      const profile = TeamProfile(
        id: 'default-native-team',
        name: 'Native',
        createdAt: 1,
      );

      await store.upsert(profile).timeout(const Duration(seconds: 2));

      final loaded = await store.tryRead(preferIsolate: false);
      expect(loaded, isNotNull);
      expect(loaded!.single.id, 'default-native-team');
    },
  );

  test('decodeProfile rejects legacy personal kind', () {
    expect(
      () => LaunchProfileIndexStore.decodeProfile({
        'id': 'p1',
        'kind': 'personal',
        'display': 'Personal',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
