import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/flashskyai_storage_roots.dart';
import 'package:teampilot/services/remote_teampilot_app_data_resolver.dart';

void main() {
  late Directory appDataRoot;

  setUp(() async {
    appDataRoot = await Directory.systemTemp.createTemp('teampilot_app_data_');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(appDataRoot.path));
  });

  tearDown(() async {
    AppPathsBootstrapper.resetForTesting();
    if (await appDataRoot.exists()) {
      await appDataRoot.delete(recursive: true);
    }
  });

  test('resolve returns local paths when not in SSH mode', () async {
    final roots = FlashskyaiStorageRoots(isSshMode: () => false);
    final snap = await roots.resolve();
    expect(snap.storageIsRemote, isFalse);
    expect(snap.teamsUiDir, AppPathsBootstrapper.current.teamsDir);
    expect(
      snap.appFlashskyaiDir.replaceAll(r'\', '/'),
      endsWith('config-profiles/flashskyai'),
    );
    expect(snap.remoteFileStore, isNull);
  });

  test('resolve falls back to local when SSH mode but no profile', () async {
    final roots = FlashskyaiStorageRoots(
      isSshMode: () => true,
      sshProfileResolver: () => null,
    );
    final snap = await roots.resolve();
    expect(snap.storageIsRemote, isFalse);
  });

  test('SSH snapshot exposes layout under teampilotRoot/config-profiles', () {
    const teampilotRoot = '/home/remote/.local/share/com.hhoa.teampilot';
    final snap = StorageRootsSnapshot(
      storageIsRemote: true,
      teampilotRoot: teampilotRoot,
      teamsUiDir: AppPaths.teamsUiDirForTeampilotRoot(teampilotRoot),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(teampilotRoot),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(teampilotRoot),
      appProjectsDir: AppPaths.appProjectsDirForTeampilotRoot(teampilotRoot),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(
        teampilotRoot,
      ),
    );
    final posix = AppPaths.posixPathContext;
    expect(snap.teampilotRoot, teampilotRoot);
    expect(snap.teamsUiDir, posix.join(teampilotRoot, 'teams'));
    expect(snap.skillsRoot, posix.join(teampilotRoot, 'skills'));
    expect(snap.appProjectsDir, posix.join(teampilotRoot, 'projects'));
    expect(snap.skillReposConfigPath, posix.join(teampilotRoot, 'skills.json'));
    expect(
      snap.appFlashskyaiDir,
      posix.join(teampilotRoot, 'config-profiles', 'flashskyai'),
    );
    expect(
      snap.layout.teamToolDir('team-a', 'flashskyai'),
      posix.join(
        teampilotRoot,
        'config-profiles',
        'teams',
        'team-a',
        'flashskyai',
      ),
    );
    expect(
      snap.layout.memberToolDir('team-a', 'sess-1', 'flashskyai'),
      posix.join(
        teampilotRoot,
        'config-profiles',
        'teams',
        'team-a',
        'members',
        'sess-1',
        'flashskyai',
      ),
    );
  });

  test('pickTeampilotRoot prefers primary when it has data', () async {
    final root = await RemoteTeampilotAppDataResolver.pickTeampilotRoot(
      primary: '/xdg/teampilot',
      legacy: '/cli/.flashskyai/teampilot',
      hasExistingData: (path) async => path.startsWith('/xdg'),
    );
    expect(root, '/xdg/teampilot');
  });

  test(
    'pickTeampilotRoot falls back to legacy when primary is empty',
    () async {
      final root = await RemoteTeampilotAppDataResolver.pickTeampilotRoot(
        primary: '/xdg/teampilot',
        legacy: '/cli/.flashskyai/teampilot',
        hasExistingData: (path) async => path.contains('.flashskyai'),
      );
      expect(root, '/cli/.flashskyai/teampilot');
    },
  );
}
