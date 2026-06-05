import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex_home_provisioner.dart';
import 'package:teampilot/services/provider/codex_proxy_launch_auth.dart';
import 'package:teampilot/services/provider/codex_team_bus_overlay.dart';

void main() {
  group('CodexProxyLaunchAuth', () {
    test('uses PROXY_MANAGED when meta.proxyTakeover is set', () {
      const provider = AppProviderConfig(
        id: 'p',
        cli: AppProviderCli.codex,
        name: 'p',
        apiKey: 'sk-real',
        config: {
          'meta': {'proxyTakeover': true},
          'configToml': 'base_url = "http://127.0.0.1:15721/v1"',
        },
      );
      final auth = CodexProxyLaunchAuth.buildAuth(provider);
      expect(auth['OPENAI_API_KEY'], 'PROXY_MANAGED');
    });
  });

  group('CodexHomeProvisioner', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('codex_home_prov_');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('writes auth.json and config.toml under codex home', () async {
      const provider = AppProviderConfig(
        id: 'deepseek',
        cli: AppProviderCli.codex,
        name: 'DeepSeek',
        apiKey: 'sk-test',
        baseUrl: 'https://api.deepseek.com',
        defaultModel: 'deepseek-v4-flash',
        config: {
          'configToml': '''
model = "deepseek-v4-flash"
[model_providers.custom]
base_url = "https://api.deepseek.com"
''',
        },
      );

      final codexHome = p.join(root.path, 'codex-home');
      await CodexHomeProvisioner(fs: LocalFilesystem()).provision(
        codexHome: codexHome,
        provider: provider,
      );

      final auth =
          jsonDecode(
                await File(p.join(codexHome, 'auth.json')).readAsString(),
              )
              as Map;
      expect(auth['OPENAI_API_KEY'], 'sk-test');

      final toml = await File(p.join(codexHome, 'config.toml')).readAsString();
      expect(toml, contains('api.deepseek.com'));
    });

    test('appends bus overlay without dropping provider toml', () async {
      const provider = AppProviderConfig(
        id: 'p',
        cli: AppProviderCli.codex,
        name: 'p',
        config: {
          'configToml': 'model = "m1"\nbase_url = "https://upstream.example.com"\n',
        },
      );
      final overlay = CodexTeamBusOverlay.build(memberId: 'w1', port: 44000);

      final codexHome = p.join(root.path, 'codex-mixed');
      await CodexHomeProvisioner(fs: LocalFilesystem()).provision(
        codexHome: codexHome,
        provider: provider,
        busOverlayToml: overlay,
      );

      final toml = await File(p.join(codexHome, 'config.toml')).readAsString();
      expect(toml, contains('upstream.example.com'));
      expect(toml, contains('[mcp_servers.teammate-bus]'));
      expect(toml, contains(':44000/mcp'));
    });

    test('injects project trust for session working directory', () async {
      const provider = AppProviderConfig(
        id: 'p',
        cli: AppProviderCli.codex,
        name: 'p',
        config: {'configToml': 'model = "m1"\n'},
      );
      const cwd = '/home/user/Document/testmixed';

      final codexHome = p.join(root.path, 'codex-trust');
      await CodexHomeProvisioner(fs: LocalFilesystem()).provision(
        codexHome: codexHome,
        provider: provider,
        trustedProjectDirectories: [cwd],
      );

      final toml = await File(p.join(codexHome, 'config.toml')).readAsString();
      expect(
        toml,
        contains('[projects."/home/user/Document/testmixed"]'),
      );
      expect(toml, contains('trust_level = "trusted"'));
    });
  });
}
