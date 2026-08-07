import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/plugin/cli_plugin_provision_cache.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  group('CliPluginProvisionCache', () {
    late Directory base;
    late LocalFilesystem fs;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('cli_plugin_cache_');
      fs = LocalFilesystem();
    });

    tearDown(() async {
      if (await base.exists()) {
        await base.delete(recursive: true);
      }
    });


    test(
      'provisionFingerprintForRegistry ignores metadata-only stamp fields',
      () {
        const legacy = '''
{
  "version": 1,
  "flavor": "flashskyai",
  "bundles": [
    {"dirName": "demo", "name": "demo", "version": "1.0.0", "mtimeMs": 100}
  ]
}
''';
        const upgraded = '''
{
  "version": 1,
  "flavor": "flashskyai",
  "teamPluginsDir": "/team/plugins",
  "teamPluginsMtimeMs": 200,
  "bundles": [
    {
      "dirName": "demo",
      "name": "demo",
      "version": "1.0.0",
      "mtimeMs": 100,
      "teamEntryName": "demo-src"
    }
  ]
}
''';
        expect(
          CliPluginProvisionCache.provisionFingerprintForRegistry(legacy),
          CliPluginProvisionCache.provisionFingerprintForRegistry(upgraded),
        );
      },
    );

    test('marketplace materialization skips when cache unchanged', () async {
      const marketplaceName = 'demo-marketplace';
      final cacheDir = Directory(
        p.join(
          base.path,
          'plugins',
          'marketplace-cache',
          'owner',
          '$marketplaceName@main',
        ),
      )..createSync(recursive: true);
      Directory(p.join(cacheDir.path, '.claude-plugin')).createSync();
      File(
        p.join(cacheDir.path, '.claude-plugin', 'marketplace.json'),
      ).writeAsStringSync(jsonEncode({'name': marketplaceName, 'plugins': []}));

      final dest = p.join(
        base.path,
        'session',
        'plugins',
        'marketplaces',
        marketplaceName,
      );
      await fs.ensureDir(dest);
      await fs.copyTree(source: cacheDir.path, destination: dest);
      await CliPluginProvisionCache.writeMarketplaceSourceStamp(
        fs: fs,
        dest: dest,
        teampilotCacheDir: cacheDir.path,
      );

      expect(
        await CliPluginProvisionCache.isMarketplaceMaterializationCurrent(
          fs: fs,
          dest: dest,
          teampilotCacheDir: cacheDir.path,
        ),
        isTrue,
      );
    });
  });
}
