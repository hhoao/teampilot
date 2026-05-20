import 'dart:io';

import 'package:teampilot/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('basePath throws before init', () {
    AppPathsBootstrapper.resetForTesting();
    expect(
      () => AppPathsBootstrapper.current.basePath,
      throwsA(isA<StateError>()),
    );
  });

  group('initialized paths', () {
    late Directory appDataRoot;

    setUp(() async {
      appDataRoot = await Directory.systemTemp.createTemp('app_storage_test_');
      AppPathsBootstrapper.setCurrentForTesting(AppPaths(appDataRoot.path));
    });

    tearDown(() async {
      AppPathsBootstrapper.resetForTesting();
      if (await appDataRoot.exists()) {
        await appDataRoot.delete(recursive: true);
      }
    });

    test('teamsDir sits next to basePath', () {
      expect(
        AppPathsBootstrapper.current.teamsDir,
        p.join(appDataRoot.path, 'teams'),
      );
    });

    test('configProfilesDir sits under basePath', () {
      expect(
        AppPathsBootstrapper.current.configProfilesDir,
        p.join(appDataRoot.path, 'config-profiles'),
      );
    });

    test('teamPilot teampilotRoot helpers join under root', () {
      const root = '/remote/.local/share/com.hhoa.teampilot';
      expect(AppPaths.teamsUiDirForTeampilotRoot(root), '$root/teams');
      expect(AppPaths.skillsDirForTeampilotRoot(root), '$root/skills');
      expect(AppPaths.appProjectsDirForTeampilotRoot(root), '$root/projects');
    });
  });
}
