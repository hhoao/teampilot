@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/post_frame_test_harness.dart';

/// Regression: a marketplace plugin shipped with executable hook scripts
/// (superpowers `hooks/run-hook.cmd`) must keep its +x bit when the bundle is
/// materialized into the session pool through the staged launch manifest.
void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('executable hook scripts keep their +x bit after session materialization',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
    const workspaceId = 'ws-int-exec';
    const sessionId = 'sess-int-exec';

    // Installed bundle (app-global pool) with an executable hook script.
    final bundleRoot = p.join(
      root,
      'plugins',
      'installed',
      'acme__demo-marketplace__demo',
    );
    await fs.ensureDir(p.join(bundleRoot, '.plugin'));
    await fs.writeString(
      p.join(bundleRoot, '.plugin', 'plugin.json'),
      '{"name":"demo","version":"1.0.0","description":""}',
    );
    await fs.ensureDir(p.join(bundleRoot, 'hooks'));
    await fs.writeString(
      p.join(bundleRoot, 'hooks', 'run-hook.cmd'),
      '#!/usr/bin/env bash\n',
    );
    await Process.run('chmod', ['+x', p.join(bundleRoot, 'hooks', 'run-hook.cmd')]);
    final srcMode = File(p.join(bundleRoot, 'hooks', 'run-hook.cmd')).statSync().mode;
    // ignore: avoid_print
    print('SRC_MODE src=${(srcMode & 0x1FF).toRadixString(8)} '
        'exec=${(srcMode & 0x49) != 0}');

    await fs.writeString(
      p.join(root, 'plugins', 'plugins.json'),
      jsonEncode({
        'plugins': [
          {
            'id': 'acme/demo-marketplace/demo',
            'name': 'demo',
            'version': '1.0.0',
            'directory': 'acme__demo-marketplace__demo',
            'marketplaceOwner': 'acme',
            'marketplaceName': 'demo-marketplace',
            'marketplaceBranch': 'main',
          },
        ],
      }),
    );

    // Marketplace cache so the session marketplace gets linked.
    const marketplaceCache = 'plugins/marketplace-cache/acme/demo-marketplace@main';
    await fs.ensureDir(p.join(root, marketplaceCache, '.claude-plugin'));
    await fs.writeString(
      p.join(root, marketplaceCache, '.claude-plugin', 'marketplace.json'),
      jsonEncode({
        'name': 'demo-marketplace',
        'owner': {'name': 'acme'},
        'plugins': [
          {
            'name': 'demo',
            'source': {
              'source': 'url',
              'url': 'https://example.com/demo.git',
            },
          },
        ],
      }),
    );

    final service = ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
    );
    final staged = await service.stageSimpleSessionLaunch(
      readDelegate: fs,
      workTeampilotRoot: root,
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: const ConfigBundle(
        pluginIds: ['acme/demo-marketplace/demo'],
      ),
      member: const TeamMemberConfig(id: 'solo', name: 'solo'),
      workingDirectory: '/workspace/simple',
    );

    await const ManifestExecutor().flush(
      manifest: staged.manifest,
      targetFs: fs,
      sourceFs: fs,
    );

    final claudeDir = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      'claude',
    );
    final materialized = File(
      p.join(
        claudeDir,
        'plugins',
        'acme__demo-marketplace__demo',
        'hooks',
        'run-hook.cmd',
      ),
    );
    expect(materialized.existsSync(), isTrue,
        reason: 'hook script must be materialized into the session pool');
    final mode = materialized.statSync().mode;
    // ignore: avoid_print
    print(
      'HOOK_EXEC mode=${(mode & 0x1FF).toRadixString(8)} '
      'exec=${(mode & 0x49) != 0}',
    );
    expect(mode & 0x49, isNot(equals(0)),
        reason: 'hook script must keep its executable bit after materialization');
  });
}
