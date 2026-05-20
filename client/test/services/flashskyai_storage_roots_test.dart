import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/flashskyai_storage_roots.dart';
import 'package:teampilot/services/remote_teampilot_app_data_resolver.dart';

void main() {
  late Directory appDataRoot;

  setUp(() async {
    appDataRoot = await Directory.systemTemp.createTemp('teampilot_app_data_');
    AppStorage.setBasePathForTesting(appDataRoot.path);
  });

  tearDown(() async {
    AppStorage.resetForTesting();
    if (await appDataRoot.exists()) {
      await appDataRoot.delete(recursive: true);
    }
  });

  test('resolve returns local paths when not in SSH mode', () async {
    final roots = FlashskyaiStorageRoots(isSshMode: () => false);
    final snap = await roots.resolve();
    expect(snap.storageIsRemote, isFalse);
    expect(snap.teamsUiDir, AppStorage.teamsDir);
    expect(snap.appFlashskyaiDir, endsWith('/config-profiles/flashskyai'));
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
      teamsUiDir: AppStorage.teamsUiDirForTeampilotRoot(teampilotRoot),
      skillsRoot: AppStorage.skillsDirForTeampilotRoot(teampilotRoot),
      skillBackupsDir: AppStorage.skillBackupsDirForTeampilotRoot(teampilotRoot),
      appProjectsDir: AppStorage.appProjectsDirForTeampilotRoot(teampilotRoot),
      skillReposConfigPath:
          AppStorage.skillReposConfigPathForTeampilotRoot(teampilotRoot),
    );
    expect(snap.teampilotRoot, teampilotRoot);
    expect(snap.teamsUiDir, '$teampilotRoot/teams');
    expect(snap.skillsRoot, '$teampilotRoot/skills');
    expect(snap.appProjectsDir, '$teampilotRoot/projects');
    expect(snap.skillReposConfigPath, '$teampilotRoot/skills.json');
    expect(snap.appFlashskyaiDir, '$teampilotRoot/config-profiles/flashskyai');
    expect(
      snap.layout.teamToolDir('team-a', 'flashskyai'),
      '$teampilotRoot/config-profiles/teams/team-a/flashskyai',
    );
    expect(
      snap.layout.memberToolDir('team-a', 'sess-1', 'flashskyai'),
      '$teampilotRoot/config-profiles/teams/team-a/members/sess-1/flashskyai',
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

  test('pickTeampilotRoot falls back to legacy when primary is empty', () async {
    final root = await RemoteTeampilotAppDataResolver.pickTeampilotRoot(
      primary: '/xdg/teampilot',
      legacy: '/cli/.flashskyai/teampilot',
      hasExistingData: (path) async => path.contains('.flashskyai'),
    );
    expect(root, '/cli/.flashskyai/teampilot');
  });
}
