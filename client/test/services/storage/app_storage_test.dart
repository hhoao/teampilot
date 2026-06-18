import 'dart:io';

import 'package:teampilot/services/storage/app_storage.dart';
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

    test('launchProfilesDir sits next to basePath', () {
      expect(
        AppPathsBootstrapper.current.launchProfilesDir,
        p.join(appDataRoot.path, 'launch-profiles'),
      );
    });

    test('cliDefaultsDir sits under basePath', () {
      expect(
        AppPathsBootstrapper.current.cliDefaultsDir,
        p.join(appDataRoot.path, 'cli-defaults'),
      );
    });

    test('workspaceDir sits under basePath', () {
      expect(
        AppPathsBootstrapper.current.workspaceDir,
        p.join(appDataRoot.path, 'workspace'),
      );
    });

    test('teamPilot teampilotRoot helpers join under root', () {
      const root = '/remote/.local/share/com.hhoa.teampilot';
      expect(AppPaths.launchProfilesDirForTeampilotRoot(root), '$root/launch-profiles');
      expect(AppPaths.skillsDirForTeampilotRoot(root), '$root/skills/installed');
      expect(
        AppPaths.skillBackupsDirForTeampilotRoot(root),
        '$root/skills/backups',
      );
      expect(
        AppPaths.skillReposConfigPathForTeampilotRoot(root),
        '$root/skills/repos.json',
      );
      expect(
        AppPaths.skillRepoCacheDirForTeampilotRoot(root),
        '$root/skills/repo-cache',
      );
      expect(
        AppPaths.workspaceDirForTeampilotRoot(root),
        '$root/workspace',
      );
      expect(
        AppPaths.cliDefaultsDirForTeampilotRoot(root),
        '$root/cli-defaults',
      );
      expect(
        AppPaths.homeWorkspaceOpenWorkspacesJsonForTeampilotRoot(root),
        '$root/ui/open-workspace-tabs.json',
      );
    });

    test('defaultTeampilotAppDataDirForHome uses POSIX separators for WSL home', () {
      expect(
        AppPaths.defaultTeampilotAppDataDirForHome('/home/hhoa'),
        '/home/hhoa/.local/share/com.hhoa.teampilot',
      );
      expect(
        AppPaths.defaultTeampilotAppDataDirForHome('/home/hhoa'),
        isNot(contains(r'\')),
      );
    });

    test('AppPaths exposes plugin paths under teampilotRoot', () {
      final root = '/tmp/tp';
      expect(AppPaths.pluginsDirForTeampilotRoot(root), '/tmp/tp/plugins/installed');
      expect(AppPaths.pluginBackupsDirForTeampilotRoot(root), '/tmp/tp/plugins/backups');
      expect(AppPaths.pluginsJsonForTeampilotRoot(root), '/tmp/tp/plugins/plugins.json');
      expect(AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(root),
        '/tmp/tp/plugins/marketplaces.json');
      expect(AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(root),
        '/tmp/tp/plugins/marketplace-cache');
      expect(AppPaths.pluginExternalCacheDirForTeampilotRoot(root),
        '/tmp/tp/plugins/external-cache');
      expect(AppPaths.mcpServersJsonForTeampilotRoot(root), '/tmp/tp/mcp/mcp_servers.json');
      expect(AppPaths.mcpBackupsDirForTeampilotRoot(root), '/tmp/tp/mcp/backups');
    });
  });
}
