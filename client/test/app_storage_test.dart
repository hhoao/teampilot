import 'dart:io';

import 'package:teampilot/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('basePath throws before init', () {
    AppStorage.resetForTesting();
    expect(() => AppStorage.basePath, throwsA(isA<StateError>()));
  });

  group('initialized paths', () {
    late Directory appDataRoot;

    setUp(() async {
      appDataRoot = await Directory.systemTemp.createTemp('app_storage_test_');
      AppStorage.setBasePathForTesting(appDataRoot.path);
    });

    tearDown(() async {
      AppStorage.resetForTesting();
      if (await appDataRoot.exists()) {
        await appDataRoot.delete(recursive: true);
      }
    });

    test('teamsDir sits next to basePath', () {
      expect(AppStorage.teamsDir, p.join(appDataRoot.path, 'teams'));
    });

    test('configProfilesDir sits under basePath', () {
      expect(
        AppStorage.configProfilesDir,
        p.join(appDataRoot.path, 'config-profiles'),
      );
    });

    test('teamPilot teampilotRoot helpers join under root', () {
      const root = '/remote/.local/share/com.hhoa.teampilot';
      expect(AppStorage.teamsUiDirForTeampilotRoot(root), '$root/teams');
      expect(AppStorage.skillsDirForTeampilotRoot(root), '$root/skills');
      expect(
        AppStorage.appProjectsDirForTeampilotRoot(root),
        '$root/projects',
      );
    });
  });
}
