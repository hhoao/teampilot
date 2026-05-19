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
    expect(snap.cliTeamsDir, AppStorage.cliTeamsDir);
    expect(snap.cliAgentsDir, AppStorage.cliAgentsDir);
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

  test('SSH snapshot uses XDG teampilot app dir + flashskyai CLI dir', () {
    const teampilotRoot = '/home/remote/.local/share/com.hhoa.teampilot';
    const dataDir = '/home/remote/.flashskyai';
    final snap = StorageRootsSnapshot(
      storageIsRemote: true,
      teampilotRoot: teampilotRoot,
      teamsUiDir: AppStorage.teamsUiDirForTeampilotRoot(teampilotRoot),
      cliTeamsDir: '$dataDir/teams',
      skillsRoot: AppStorage.skillsDirForTeampilotRoot(teampilotRoot),
      skillBackupsDir: AppStorage.skillBackupsDirForTeampilotRoot(teampilotRoot),
      cliSkillsDir: '$dataDir/skills',
      cliAgentsDir: '$dataDir/agents',
      appProjectsDir: AppStorage.appProjectsDirForTeampilotRoot(teampilotRoot),
      skillReposConfigPath:
          AppStorage.skillReposConfigPathForTeampilotRoot(teampilotRoot),
      remoteCliDataDir: dataDir,
    );
    expect(snap.teampilotRoot, teampilotRoot);
    expect(snap.teamsUiDir, '$teampilotRoot/teams');
    expect(snap.cliTeamsDir, '/home/remote/.flashskyai/teams');
    expect(snap.skillsRoot, '$teampilotRoot/skills');
    expect(snap.cliSkillsDir, '/home/remote/.flashskyai/skills');
    expect(snap.cliAgentsDir, '/home/remote/.flashskyai/agents');
    expect(snap.appProjectsDir, '$teampilotRoot/projects');
    expect(snap.skillReposConfigPath, '$teampilotRoot/skills.json');
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
