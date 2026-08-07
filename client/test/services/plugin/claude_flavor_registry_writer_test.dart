import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/claude_flavor_registry_writer.dart';

void main() {
  group('ClaudeFlavorRegistryWriter marketplace materialization', () {
    late Directory base;
    late LocalFilesystem fs;
    late String teampilotRoot;
    late String cacheDir;
    late String configDir;
    late String dest;

    const marketplaceName = 'demo';

    setUp(() async {
      base = await Directory.systemTemp.createTemp('claude_writer_');
      fs = LocalFilesystem();
      teampilotRoot = base.path;
      cacheDir = p.join(
        teampilotRoot,
        'plugins',
        'marketplace-cache',
        'owner',
        '$marketplaceName@main',
      );
      Directory(p.join(cacheDir, '.claude-plugin')).createSync(recursive: true);
      File(
        p.join(cacheDir, '.claude-plugin', 'marketplace.json'),
      ).writeAsStringSync(
        jsonEncode({'name': marketplaceName, 'plugins': []}),
      );

      configDir = p.join(base.path, 'session');
      dest = p.join(configDir, 'plugins', 'marketplaces', marketplaceName);
      Directory(p.dirname(dest)).createSync(recursive: true);
      Link(dest).createSync(cacheDir);
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    Future<void> writeWithEnabledPlugin() {
      final memberPluginsDir = p.join(base.path, 'member', 'plugins');
      Directory(p.join(memberPluginsDir, 'demo-bundle', '.claude-plugin'))
          .createSync(recursive: true);
      File(
        p.join(memberPluginsDir, 'demo-bundle', '.claude-plugin', 'plugin.json'),
      ).writeAsStringSync(
        jsonEncode({'name': 'demo-plugin', 'version': '1.0.0'}),
      );

      final catalog = [
        Plugin(
          id: 'owner/demo-plugin',
          name: 'demo-plugin',
          description: 'demo plugin',
          version: '1.0.0',
          directory: 'demo-bundle',
          marketplaceOwner: 'owner',
          marketplaceName: marketplaceName,
          installedAt: 0,
          updatedAt: 0,
        ),
      ];

      return ClaudeFlavorRegistryWriter(
        fs: fs,
        teampilotRoot: teampilotRoot,
      ).write(
        configDir: configDir,
        memberPluginsDir: memberPluginsDir,
        tool: CliTool.claude,
        enabledIds: const ['owner/demo-plugin'],
        paths: claudePluginManifestPaths,
        catalog: catalog,
      );
    }

    test('keeps a pre-seeded marketplace symlink instead of reverting to copy',
        () async {
      await writeWithEnabledPlugin();

      expect(Link(dest).existsSync(), isTrue,
          reason: 'pre-seeded symlink must survive materialization');
      expect(Link(dest).targetSync(), cacheDir);
      // The linked marketplace still resolves to the shared cache content.
      expect(
        File(p.join(dest, '.claude-plugin', 'marketplace.json')).existsSync(),
        isTrue,
      );
    });

    test('does not write a materialization stamp into the shared cache', () async {
      await writeWithEnabledPlugin();

      expect(
        File(p.join(cacheDir, '.teampilot-marketplace-source-stamp.json'))
            .existsSync(),
        isFalse,
        reason: 'shared cache must stay unpolluted by per-session stamps',
      );
    });
  });
}
