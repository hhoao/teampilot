import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/codex/codex_bootstrap_entry.dart';
import 'package:teampilot/services/cli/codex/provider/codex_provider_credentials_service.dart';
import 'package:teampilot/services/cli/codex/provider/codex_toml_parser.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('codex registers AcpCapability that spawns the adapter', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.codex);
    expect(cap, isNotNull);
    // Resolves via PATH / ~/.local/bin when installed; bare name otherwise.
    final exe = cap!.agentExecutable('/usr/bin/codex');
    expect(exe, endsWith('codex-acp'));
    expect(cap.launchArgCandidates(exe), [
      [exe],
    ]);
  });

  group('bootstrap acpAuthSource', () {
    late CodexProviderCredentialsService credentials;

    setUp(() {
      final fs = InMemoryFilesystem();
      credentials = CodexProviderCredentialsService(
        fs: fs,
        basePath: '/data/tp',
        storage: fakeHomeStorage(filesystem: fs),
      );
    });

    test('auth source is invoked at buildEnvironment, not at registration', () {
      var calls = 0;
      final registry = CliToolRegistry();
      registerBuiltInCliTools(
        registry,
        bootstrap: CliBootstrap({
          CliTool.codex: CodexBootstrapEntry(
            credentialsService: credentials,
            acpAuthSource: () {
              calls++;
              return codexAcpAuthForProvider(null);
            },
          ),
        }, storage: fakeHomeStorage()),
      );
      expect(calls, 0);
      final env = registry
          .capability<AcpCapability>(CliTool.codex)!
          .buildEnvironment(sessionToolDir: '/s/tool', workingDirectory: '/w');
      expect(calls, 1);
      expect(env['CODEX_HOME'], '/s/tool');
    });

    test('official provider yields official auth without apiKey', () {
      final auth = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'openai-official',
          cli: CliTool.codex,
          name: 'Official',
          category: AppProviderCategory.official,
          isOfficial: true,
        ),
      );
      expect(auth.official, isTrue);
      expect(auth.apiKey, isNull);
    });

    test('key provider maps OPENAI_API_KEY from settings env', () {
      final auth = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'p',
          cli: CliTool.codex,
          name: 'P',
          config: {
            'env': {'OPENAI_API_KEY': ' sk-1 '},
          },
        ),
      );
      expect(auth.official, isFalse);
      expect(auth.apiKey, 'sk-1');
    });

    test('key provider falls back to apiKey field', () {
      final auth = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'p',
          cli: CliTool.codex,
          name: 'P',
          apiKey: ' sk-field ',
        ),
      );
      expect(auth.official, isFalse);
      expect(auth.apiKey, 'sk-field');
    });

    test('PROXY_MANAGED / empty yields empty auth', () {
      final proxy = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'p',
          cli: CliTool.codex,
          name: 'P',
          config: {
            'env': {'OPENAI_API_KEY': CodexTomlParser.proxyManagedToken},
          },
        ),
      );
      expect(proxy.official, isFalse);
      expect(proxy.apiKey, isNull);

      final emptyEnv = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'e',
          cli: CliTool.codex,
          name: 'E',
          config: {
            'env': {'OPENAI_API_KEY': ''},
          },
        ),
      );
      expect(emptyEnv.official, isFalse);
      expect(emptyEnv.apiKey, isNull);

      final none = codexAcpAuthForProvider(null);
      expect(none.official, isFalse);
      expect(none.apiKey, isNull);

      final otherCli = codexAcpAuthForProvider(
        const AppProviderConfig(
          id: 'c',
          cli: CliTool.claude,
          name: 'C',
          apiKey: 'sk-other',
        ),
      );
      expect(otherCli.official, isFalse);
      expect(otherCli.apiKey, isNull);
    });
  });

  group('pickCodexAcpProvider', () {
    const official = AppProviderConfig(
      id: 'openai-official',
      cli: CliTool.codex,
      name: 'Official',
      category: AppProviderCategory.official,
      isOfficial: true,
    );
    const key = AppProviderConfig(
      id: 'k',
      cli: CliTool.codex,
      name: 'K',
      config: {
        'env': {'OPENAI_API_KEY': ' sk-1 '},
      },
    );
    const providers = [official, key];

    test('selected key id returns that row', () {
      expect(
        pickCodexAcpProvider(providers: providers, selectedId: 'k'),
        same(key),
      );
    });

    test('selected official id returns that row', () {
      expect(
        pickCodexAcpProvider(
          providers: providers,
          selectedId: 'openai-official',
        ),
        same(official),
      );
    });

    test('missing or empty selected id falls back to official', () {
      expect(
        pickCodexAcpProvider(providers: providers, selectedId: null),
        same(official),
      );
      expect(
        pickCodexAcpProvider(providers: providers, selectedId: ''),
        same(official),
      );
      expect(
        pickCodexAcpProvider(providers: providers, selectedId: '  '),
        same(official),
      );
      expect(
        pickCodexAcpProvider(providers: providers, selectedId: 'missing'),
        same(official),
      );
    });
  });
}
