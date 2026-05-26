import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/flashskyai_storage_roots.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/remote_teampilot_app_data_resolver.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory appDataRoot;

  setUp(() async {
    appDataRoot = await Directory.systemTemp.createTemp('teampilot_app_data_');
    final paths = AppPaths(appDataRoot.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: appDataRoot.path,
      cwd: appDataRoot.path,
    );
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
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
      fs: LocalFilesystem(pathContext: AppPaths.posixPathContext),
      teamsUiDir: AppPaths.teamsUiDirForTeampilotRoot(teampilotRoot),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(teampilotRoot),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(teampilotRoot),
      appProjectsDir: AppPaths.appProjectsDirForTeampilotRoot(teampilotRoot),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(
        teampilotRoot,
      ),
      pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(teampilotRoot),
      pluginBackupsDir: AppPaths.pluginBackupsDirForTeampilotRoot(teampilotRoot),
      pluginsJsonPath: AppPaths.pluginsJsonForTeampilotRoot(teampilotRoot),
      pluginMarketplacesConfigPath:
          AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(teampilotRoot),
      pluginMarketplaceCacheDir:
          AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(teampilotRoot),
      pluginExternalCacheDir:
          AppPaths.pluginExternalCacheDirForTeampilotRoot(teampilotRoot),
    );
    final posix = AppPaths.posixPathContext;
    expect(snap.teampilotRoot, teampilotRoot);
    expect(snap.teamsUiDir, posix.join(teampilotRoot, 'teams'));
    expect(snap.skillsRoot, posix.join(teampilotRoot, 'skills', 'installed'));
    expect(snap.appProjectsDir, posix.join(teampilotRoot, 'projects'));
    expect(
      snap.skillReposConfigPath,
      posix.join(teampilotRoot, 'skills', 'repos.json'),
    );
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

  test('reinstallAndResolve invokes reinstallContext before resolving', () async {
    var reinstallCalls = 0;
    final roots = FlashskyaiStorageRoots(
      isSshMode: () => false,
      reinstallContext: () async {
        reinstallCalls++;
        return RuntimeStorageContext.current;
      },
    );

    await roots.reinstallAndResolve();

    expect(reinstallCalls, 1);
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
