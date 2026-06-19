import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/plugin/cli_plugin_layout.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../support/in_memory_filesystem.dart';

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
  group('projectBundleToFlavor flashskyai', () {
    test('writes .flashskyai-plugin from neutral .plugin manifest', () async {
      final fs = InMemoryFilesystem();
      const root = '/bundle';
      await fs.writeString(
        '$root/.plugin/plugin.json',
        '{"name":"demo"}',
      );

      await CliPluginLayout.projectBundleToFlavor(
        fs,
        root,
        flashskyaiPluginManifestPaths,
      );

      expect(
        await fs.readString('$root/.flashskyai-plugin/plugin.json'),
        '{"name":"demo"}',
      );
    });

    test('falls back to .claude-plugin source manifest', () async {
      final fs = InMemoryFilesystem();
      const root = '/bundle';
      await fs.writeString(
        '$root/.claude-plugin/plugin.json',
        '{"name":"claude"}',
      );

      await CliPluginLayout.projectBundleToFlavor(
        fs,
        root,
        flashskyaiPluginManifestPaths,
      );

      expect(
        await fs.readString('$root/.flashskyai-plugin/plugin.json'),
        '{"name":"claude"}',
      );
    });

    test('overwrites existing target manifest from neutral source', () async {
      final fs = InMemoryFilesystem();
      const root = '/bundle';
      await fs.writeString(
        '$root/.flashskyai-plugin/plugin.json',
        '{"name":"native"}',
      );
      await fs.writeString(
        '$root/.plugin/plugin.json',
        '{"name":"neutral"}',
      );

      await CliPluginLayout.projectBundleToFlavor(
        fs,
        root,
        flashskyaiPluginManifestPaths,
      );

      expect(
        await fs.readString('$root/.flashskyai-plugin/plugin.json'),
        '{"name":"neutral"}',
      );
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
        paths: flashskyaiPluginManifestPaths,
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

    test('copies claude bundles into member dir without flashskyai manifest', () async {
      final fs = LocalFilesystem();
      final teamPlugins = Directory(p.join(base.path, 'team', 'plugins'))
        ..createSync(recursive: true);
      final bundle = Directory(p.join(teamPlugins.path, 'demo'))..createSync();
      Directory(p.join(bundle.path, '.claude-plugin')).createSync();
      File(p.join(bundle.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
        '{"name":"demo","version":"1.0.0"}',
      );
      Directory(p.join(bundle.path, '.flashskyai-plugin')).createSync();
      File(p.join(bundle.path, '.flashskyai-plugin', 'plugin.json'))
          .writeAsStringSync('{"name":"demo","version":"1.0.0"}');

      final memberPlugins = p.join(base.path, 'member', 'plugins');
      await CliPluginLayout.copyBundlesToMember(
        fs: fs,
        teamPluginsDir: teamPlugins.path,
        memberPluginsDir: memberPlugins,
        paths: claudePluginManifestPaths,
      );

      final memberBundle = p.join(memberPlugins, 'demo');
      expect(Directory(memberBundle).existsSync(), isTrue);
      if (Platform.isLinux || Platform.isMacOS) {
        expect(Link(memberBundle).existsSync(), isFalse);
      }
      expect(
        File(p.join(memberBundle, '.claude-plugin', 'plugin.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(memberBundle, '.flashskyai-plugin', 'plugin.json')).existsSync(),
        isFalse,
      );
    });

    test('always copies member bundles (no member symlink)', () async {
      final fs = LocalFilesystem();
      final teamPlugins = Directory(p.join(base.path, 'team', 'plugins'))
        ..createSync(recursive: true);
      final bundle = Directory(p.join(teamPlugins.path, 'demo'))..createSync();
      Directory(p.join(bundle.path, '.claude-plugin')).createSync();
      File(p.join(bundle.path, '.claude-plugin', 'plugin.json')).writeAsStringSync(
        '{"name":"demo","version":"1.0.0"}',
      );

      final memberPlugins = p.join(base.path, 'member', 'plugins');
      await CliPluginLayout.copyBundlesToMember(
        fs: fs,
        teamPluginsDir: teamPlugins.path,
        memberPluginsDir: memberPlugins,
        paths: flashskyaiPluginManifestPaths,
      );

      final memberBundle = p.join(memberPlugins, 'demo');
      expect(Directory(memberBundle).existsSync(), isTrue);
      if (Platform.isLinux || Platform.isMacOS) {
        expect(Link(memberBundle).existsSync(), isFalse);
      }
      expect(
        File(p.join(memberBundle, '.flashskyai-plugin', 'plugin.json')).existsSync(),
        isTrue,
      );
    });

    test('falls back to copy when symlinks are unavailable', () async {
      final fs = _NoSymlinkFilesystem();
      const teamPlugins = '/team/plugins';
      const memberPlugins = '/member/plugins';
      await fs.ensureDir('$teamPlugins/demo/.claude-plugin');
      await fs.writeString(
        '$teamPlugins/demo/.claude-plugin/plugin.json',
        '{"name":"demo","version":"1.0.0"}',
      );

      await CliPluginLayout.copyBundlesToMember(
        fs: fs,
        teamPluginsDir: teamPlugins,
        memberPluginsDir: memberPlugins,
        paths: claudePluginManifestPaths,
      );

      expect(fs.symlinks.containsKey('$memberPlugins/demo'), isFalse);
      expect(
        await fs.readString('$memberPlugins/demo/.claude-plugin/plugin.json'),
        isNotNull,
      );
    });
  });
}
