import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_config_sidecar.dart';

void main() {
  group('CodexConfigSidecar', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_sidecar_');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('persistFromLiveCodexHome copies referenced file into provider dir', () async {
      const configToml = 'model_catalog_json = "cc-switch-model-catalog.json"\n';
      final liveHome = p.join(root.path, 'user');
      final codexHome = p.join(liveHome, '.codex');
      await Directory(codexHome).create(recursive: true);
      await File(p.join(codexHome, 'cc-switch-model-catalog.json'))
          .writeAsString('{"models":[]}');

      final providerDir = p.join(root.path, 'providers', 'deepseek');
      await Directory(providerDir).create(recursive: true);

      await CodexConfigSidecar.persistFromLiveCodexHome(
        fs: LocalFilesystem(),
        providerDir: providerDir,
        configToml: configToml,
        liveCodexHome: liveHome,
      );

      expect(
        await File(p.join(providerDir, 'cc-switch-model-catalog.json')).exists(),
        isTrue,
      );
    });
  });
}
