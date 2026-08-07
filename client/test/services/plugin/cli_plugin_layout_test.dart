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
      await fs.writeString('$root/.plugin/plugin.json', '{"name":"demo"}');

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
      await fs.writeString('$root/.plugin/plugin.json', '{"name":"neutral"}');

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

}
