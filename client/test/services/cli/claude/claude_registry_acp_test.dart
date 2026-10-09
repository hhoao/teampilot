import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/claude/claude_bootstrap_entry.dart';
import 'package:teampilot/services/cli/claude/provider/claude_provider_credentials_service.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/cli_bootstrap.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('claude registers AcpCapability that spawns the adapter', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final cap = registry.capability<AcpCapability>(CliTool.claude);
    expect(cap, isNotNull);
    expect(cap!.agentExecutable('/usr/bin/claude'), 'claude-agent-acp');
    expect(cap.launchArgCandidates('claude-agent-acp'), [
      ['claude-agent-acp'],
    ]);
  });

  group('bootstrap acpAuthSource', () {
    late ClaudeProviderCredentialsService credentials;

    setUp(() {
      final fs = InMemoryFilesystem();
      credentials = ClaudeProviderCredentialsService(
        fs: fs,
        basePath: '/data/tp',
        resolveHomeDirectory: () => '/home/user',
        storage: fakeHomeStorage(filesystem: fs),
      );
    });

    test('auth source is invoked at buildEnvironment, not at registration', () {
      var calls = 0;
      final registry = CliToolRegistry();
      registerBuiltInCliTools(
        registry,
        bootstrap: CliBootstrap({
          CliTool.claude: ClaudeBootstrapEntry(
            credentialsService: credentials,
            acpAuthSource: () {
              calls++;
              return claudeAcpAuthForProvider(null, credentials);
            },
          ),
        }, storage: fakeHomeStorage()),
      );
      expect(calls, 0);
      final env = registry
          .capability<AcpCapability>(CliTool.claude)!
          .buildEnvironment(sessionToolDir: '/s/tool', workingDirectory: '/w');
      expect(calls, 1);
      expect(env['CLAUDE_CONFIG_DIR'], '/s/tool/claude');
    });

    test('official provider yields official auth without key or token', () {
      final auth = claudeAcpAuthForProvider(
        const AppProviderConfig(
          id: 'claude-official',
          cli: CliTool.claude,
          name: 'Official',
          category: AppProviderCategory.official,
        ),
        credentials,
      );
      expect(auth.official, isTrue);
      expect(
        auth.officialCredentialsPath,
        '/home/user/.claude/.credentials.json',
      );
      expect(auth.apiKey, isNull);
      expect(auth.authToken, isNull);
    });

    test('settings env key / token map to apiKey / authToken', () {
      final key = claudeAcpAuthForProvider(
        const AppProviderConfig(
          id: 'k',
          cli: CliTool.claude,
          name: 'K',
          config: {
            'env': {'ANTHROPIC_API_KEY': ' sk-1 '},
          },
        ),
        credentials,
      );
      expect(key.official, isFalse);
      expect(key.apiKey, 'sk-1');
      expect(key.authToken, isNull);

      final token = claudeAcpAuthForProvider(
        const AppProviderConfig(
          id: 't',
          cli: CliTool.claude,
          name: 'T',
          config: {
            'env': {'ANTHROPIC_AUTH_TOKEN': 'tok-1'},
          },
        ),
        credentials,
      );
      expect(token.authToken, 'tok-1');
      expect(token.apiKey, isNull);
    });

    test('no provider / no key yields empty auth', () {
      final none = claudeAcpAuthForProvider(null, credentials);
      expect(none.official, isFalse);
      expect(none.apiKey, isNull);
      expect(none.authToken, isNull);
    });
  });

  group('pickClaudeAcpProvider', () {
    const official = AppProviderConfig(
      id: 'claude-official',
      cli: CliTool.claude,
      name: 'Official',
      category: AppProviderCategory.official,
    );
    const key = AppProviderConfig(
      id: 'k',
      cli: CliTool.claude,
      name: 'K',
      config: {
        'env': {'ANTHROPIC_API_KEY': ' sk-1 '},
      },
    );
    const providers = [official, key];

    test('selected key id returns that row', () {
      expect(
        pickClaudeAcpProvider(providers: providers, selectedId: 'k'),
        same(key),
      );
    });

    test('selected official id returns that row', () {
      expect(
        pickClaudeAcpProvider(
          providers: providers,
          selectedId: 'claude-official',
        ),
        same(official),
      );
    });

    test('missing or empty selected id returns null', () {
      expect(
        pickClaudeAcpProvider(providers: providers, selectedId: null),
        isNull,
      );
      expect(
        pickClaudeAcpProvider(providers: providers, selectedId: ''),
        isNull,
      );
      expect(
        pickClaudeAcpProvider(providers: providers, selectedId: '  '),
        isNull,
      );
      expect(
        pickClaudeAcpProvider(providers: providers, selectedId: 'missing'),
        isNull,
      );
    });
  });
}
