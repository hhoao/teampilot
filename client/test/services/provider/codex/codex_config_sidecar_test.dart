import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/codex/provider/codex_config_sidecar.dart';
import 'package:teampilot/services/cli/codex/provider/codex_home_provisioner.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:toml/toml.dart';

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

    test('parseRefs reads model_catalog_json regardless of quote style', () {
      const doubleQuoted =
          'model_catalog_json = "cc-switch-model-catalog.json"\n';
      const singleQuoted =
          "model_catalog_json = 'cc-switch-model-catalog.json'\n";

      expect(
        CodexConfigSidecar.parseRefs(doubleQuoted).single.relativePath,
        'cc-switch-model-catalog.json',
      );
      expect(
        CodexConfigSidecar.parseRefs(singleQuoted).single.relativePath,
        'cc-switch-model-catalog.json',
      );
    });

    test('parseRefs survives TomlDocument round-trip serialization', () {
      const original =
          'model_catalog_json = "cc-switch-model-catalog.json"\nmodel = "m1"\n';
      final roundTripped = '${TomlDocument.parse(original)}\n';

      expect(
        CodexConfigSidecar.parseRefs(roundTripped).single.relativePath,
        'cc-switch-model-catalog.json',
      );
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

    test(
      'materializeIntoCodexHome copies sidecar after TomlDocument round-trip',
      () async {
        const providerToml = '''
model = "deepseek-v4-flash"
model_catalog_json = "cc-switch-model-catalog.json"
''';
        final sessionToml = '${TomlDocument.parse(providerToml)}\n';

        final providerDir = p.join(root.path, 'provider-dir');
        await Directory(providerDir).create(recursive: true);
        await File(
          p.join(providerDir, 'cc-switch-model-catalog.json'),
        ).writeAsString('{"models":[]}');

        final codexHome = p.join(root.path, 'codex-home');
        await CodexConfigSidecar.materializeIntoCodexHome(
          fs: LocalFilesystem(),
          providerDir: providerDir,
          codexHome: codexHome,
          configToml: sessionToml,
        );

        expect(
          await File(
            p.join(codexHome, 'cc-switch-model-catalog.json'),
          ).exists(),
          isTrue,
        );
      },
    );

    test(
      'materializeIntoCodexHome fails fast when referenced sidecar is missing',
      () async {
        const sessionToml =
            "model_catalog_json = 'cc-switch-model-catalog.json'\n";

        await expectLater(
          CodexConfigSidecar.materializeIntoCodexHome(
            fs: LocalFilesystem(),
            providerDir: p.join(root.path, 'empty-provider'),
            codexHome: p.join(root.path, 'codex-home'),
            configToml: sessionToml,
          ),
          throwsA(isA<CodexConfigSidecarException>()),
        );
      },
    );

    test(
      'CodexHomeProvisioner materializes sidecars from round-tripped config',
      () async {
        const providerToml = '''
model = "deepseek-v4-flash"
model_catalog_json = "cc-switch-model-catalog.json"
''';
        final providerDir = p.join(root.path, 'provider-dir');
        await Directory(providerDir).create(recursive: true);
        await File(
          p.join(providerDir, 'cc-switch-model-catalog.json'),
        ).writeAsString('{"models":[]}');

        final codexHome = p.join(root.path, 'codex-home');
        final existingToml = '${TomlDocument.parse(providerToml)}\n';
        await Directory(codexHome).create(recursive: true);
        await File(p.join(codexHome, 'config.toml')).writeAsString(existingToml);

        await CodexHomeProvisioner(fs: LocalFilesystem()).provision(
          codexHome: codexHome,
          provider: const AppProviderConfig(
            id: 'deepseek',
            cli: CliTool.codex,
            name: 'DeepSeek',
            config: {
              'configToml': providerToml,
            },
          ),
          providerDir: providerDir,
        );

        expect(
          await File(
            p.join(codexHome, 'cc-switch-model-catalog.json'),
          ).exists(),
          isTrue,
        );
      },
    );
  });
}
