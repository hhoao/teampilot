import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli_plugin_layout.dart';
import 'package:teampilot/services/cli_plugin_manifest_flavor.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../support/in_memory_filesystem.dart';

class _NoSymlinkFilesystem extends InMemoryFilesystem {
  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    return false;
  }
}

void main() {
  group('normalizeBundleForFlavor flashskyai', () {
    test('symlinks .flashskyai-plugin to .claude-plugin when missing', () async {
      final fs = InMemoryFilesystem();
      const root = '/bundle';
      await fs.ensureDir('$root/.claude-plugin');
      await fs.writeString(
        '$root/.claude-plugin/plugin.json',
        '{"name":"demo"}',
      );

      await CliPluginLayout.normalizeBundleForFlavor(
        fs,
        root,
        CliPluginManifestFlavor.flashskyai,
      );

      expect(fs.symlinks['$root/.flashskyai-plugin'], '$root/.claude-plugin');
    });

    test('copies manifest dir when symlink is unavailable', () async {
      final fs = _NoSymlinkFilesystem();
      const root = '/bundle';
      await fs.ensureDir('$root/.claude-plugin');
      await fs.writeString(
        '$root/.claude-plugin/plugin.json',
        '{"name":"demo"}',
      );

      await CliPluginLayout.normalizeBundleForFlavor(
        fs,
        root,
        CliPluginManifestFlavor.flashskyai,
      );

      expect(fs.symlinks.containsKey('$root/.flashskyai-plugin'), isFalse);
      expect(
        await fs.readString('$root/.flashskyai-plugin/plugin.json'),
        '{"name":"demo"}',
      );
    });

    test('skips when .flashskyai-plugin already exists', () async {
      final fs = InMemoryFilesystem();
      const root = '/bundle';
      await fs.writeString(
        '$root/.flashskyai-plugin/plugin.json',
        '{"name":"native"}',
      );
      await fs.writeString(
        '$root/.claude-plugin/plugin.json',
        '{"name":"claude"}',
      );

      await CliPluginLayout.normalizeBundleForFlavor(
        fs,
        root,
        CliPluginManifestFlavor.flashskyai,
      );

      expect(
        await fs.readString('$root/.flashskyai-plugin/plugin.json'),
        '{"name":"native"}',
      );
      expect(fs.symlinks.containsKey('$root/.flashskyai-plugin'), isFalse);
    });
  });

  group('copyBundlesToMember flavor', () {
    late Directory base;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cli_plugin_layout_');
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });

    test('adds .flashskyai-plugin on flashskyai member copy only', () async {
      final fs = LocalFilesystem();
      final teamPlugins = Directory(p.join(base.path, 'team', 'plugins'))
        ..createSync(recursive: true);
      final bundle = Directory(p.join(teamPlugins.path, 'demo'))
        ..createSync();
      Directory(p.join(bundle.path, '.claude-plugin')).createSync();
      File(p.join(bundle.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
        '{"name":"demo","version":"1.0.0"}',
      );

      final memberPlugins = p.join(base.path, 'member', 'plugins');
      await CliPluginLayout.copyBundlesToMember(
        fs: fs,
        teamPluginsDir: teamPlugins.path,
        memberPluginsDir: memberPlugins,
        flavor: CliPluginManifestFlavor.flashskyai,
      );

      final copied = p.join(memberPlugins, 'demo');
      expect(
        File(p.join(copied, '.flashskyai-plugin', 'plugin.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(copied, '.claude-plugin', 'plugin.json')).existsSync(),
        isTrue,
      );
    });
  });
}
