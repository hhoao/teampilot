@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/post_frame_test_harness.dart';

/// A marketplace plugin (superpowers-style: shipped via a marketplace with an
/// external URL source, not a git-subdir inside the marketplace clone).
void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('marketplace plugin reaches the session with native registration',
      () async {
    final fs = AppStorage.fs;
    final root = AppStorage.paths.basePath;
    final layout = RuntimeLayout(teampilotRoot: root, fs: fs);
    const workspaceId = 'ws-int';
    const sessionId = 'sess-int';

    // Installed bundle (app-global pool).
    await fs.ensureDir(
      p.join(root, 'plugins', 'installed', 'acme__demo-marketplace__demo', '.plugin'),
    );
    await fs.writeString(
      p.join(
        root,
        'plugins',
        'installed',
        'acme__demo-marketplace__demo',
        '.plugin',
        'plugin.json',
      ),
      '{"name":"demo","version":"1.0.0","description":""}',
    );
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

    await ConfigProfileService(
      basePath: root,
      fs: fs,
      layout: layout,
    ).prepareSimpleSessionLaunch(
      workspaceId: workspaceId,
      sessionId: sessionId,
      runtimeBundle: const ConfigBundle(
        pluginIds: ['acme/demo-marketplace/demo'],
      ),
      member: const TeamMemberConfig(id: 'solo', name: 'solo'),
      workingDirectory: '/workspace/simple',
    );

    final claudeDir = layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      'claude',
    );
    final pluginsDir = p.join(claudeDir, 'plugins');

    // Pool populated with the enabled bundle.
    expect(
      Directory(p.join(pluginsDir, 'acme__demo-marketplace__demo')).existsSync(),
      isTrue,
      reason: 'workspace-enabled marketplace plugin must be materialized',
    );

    // Native registration under the marketplace-scoped key.
    final installed = jsonDecode(
      File(p.join(pluginsDir, 'installed_plugins.json')).readAsStringSync(),
    ) as Map;
    expect(
      (installed['plugins'] as Map).keys,
      contains('demo@demo-marketplace'),
    );

    final settings = jsonDecode(
      File(p.join(claudeDir, 'settings.json')).readAsStringSync(),
    ) as Map;
    expect(
      (settings['enabledPlugins'] as Map).keys,
      contains('demo@demo-marketplace'),
    );

    // Marketplace materialized into the session config dir.
    expect(
      Directory(p.join(pluginsDir, 'marketplaces', 'demo-marketplace'))
          .existsSync(),
      isTrue,
      reason: 'the marketplace the plugin ships from must be linked',
    );

    // known_marketplaces.json records a GitHub source, which Claude Code
    // requires (reserved names reject directory sources).
    final known = jsonDecode(
      File(p.join(pluginsDir, 'known_marketplaces.json')).readAsStringSync(),
    ) as Map;
    final marketplace = (known['demo-marketplace'] as Map);
    expect((marketplace['source'] as Map), {
      'source': 'github',
      'repo': 'acme/demo-marketplace',
    });
  });
}
