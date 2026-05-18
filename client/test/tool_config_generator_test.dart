import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/tool_config_generator.dart';

void main() {
  late ToolConfigGenerator generator;
  late Directory temp;

  setUp(() async {
    generator = const ToolConfigGenerator();
    temp = await Directory.systemTemp.createTemp('tool_cfg_gen_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('builds flashskyai llm_config from unified provider', () {
    final provider = AppProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      enabledTools: const [AppProviderTool.flashskyai],
      toolConfigs: const AppProviderToolConfigs(
        flashskyai: AppProviderToolConfigPayload(
          unknownFields: {'provider_type': 'openai'},
        ),
      ),
    );

    final llm = generator.buildFlashskyaiLlmConfig(provider);
    expect(llm.providers['deepseek']?.baseUrl, 'https://api.deepseek.com');
    expect(llm.providers['deepseek']?.apiKey, 'sk-test');
    expect(llm.providers['deepseek']?.providerType, 'openai');
    expect(llm.models['deepseek-default']?.model, 'deepseek-chat');
  });

  test('builds codex auth and config.toml for third-party provider', () {
    final provider = AppProviderConfig(
      id: 'My Provider',
      name: 'My Provider',
      apiKey: 'codex-key',
      baseUrl: 'https://api.example.com/v1',
      defaultModel: 'gpt-5.4',
      category: AppProviderCategory.thirdParty,
      enabledTools: const [AppProviderTool.codex],
    );

    final auth = generator.buildCodexAuth(provider);
    expect(auth['OPENAI_API_KEY'], 'codex-key');

    final toml = generator.buildCodexConfigToml(provider);
    expect(generator.validateCodexToml(toml), isNull);
    expect(toml, contains('model_provider = "my_provider"'));
    expect(toml, contains('base_url = "https://api.example.com/v1"'));
  });

  test('keeps codex config-only fields out of auth.json', () {
    final provider = AppProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      apiKey: 'codex-key',
      baseUrl: 'https://api.deepseek.com',
      enabledTools: const [AppProviderTool.codex],
      toolConfigs: const AppProviderToolConfigs(
        codex: AppProviderToolConfigPayload(
          unknownFields: {
            'wire_api': 'responses',
            'model': 'deepseek-chat',
            'base_url': 'https://api.deepseek.com',
            'custom_auth_value': 'kept',
          },
        ),
      ),
    );

    final auth = generator.buildCodexAuth(provider);
    expect(auth['OPENAI_API_KEY'], 'codex-key');
    expect(auth['custom_auth_value'], 'kept');
    expect(auth, isNot(contains('wire_api')));
    expect(auth, isNot(contains('model')));
    expect(auth, isNot(contains('base_url')));
  });

  test('reuses existing model_provider from team config.toml', () {
    const existing = '''
model_provider = "legacy_custom"
model = "gpt-5.4"
''';
    final provider = AppProviderConfig(
      id: 'renamed',
      name: 'Renamed',
      baseUrl: 'https://api.example.com/v1',
      enabledTools: const [AppProviderTool.codex],
    );

    final toml = generator.buildCodexConfigToml(
      provider,
      existingConfigToml: existing,
    );
    expect(toml, contains('model_provider = "legacy_custom"'));
    expect(toml, isNot(contains('model_provider = "renamed"')));
  });

  test('builds claude settings.json with env overrides', () {
    final provider = AppProviderConfig(
      id: 'ds',
      name: 'DeepSeek',
      enabledTools: const [AppProviderTool.claude],
      toolConfigs: const AppProviderToolConfigs(
        claude: AppProviderToolConfigPayload(
          unknownFields: {
            'env': {
              'ANTHROPIC_BASE_URL': 'https://api.deepseek.com',
              'ANTHROPIC_API_KEY': 'sk-claude',
            },
          },
        ),
      ),
    );

    final settings = generator.buildClaudeSettings(provider);
    final env = settings['env'] as Map;
    expect(env['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com');
    expect(env['ANTHROPIC_API_KEY'], 'sk-claude');
  });

  test('uses configured claude api key field', () {
    final provider = AppProviderConfig(
      id: 'claude-proxy',
      name: 'Claude Proxy',
      apiKey: 'sk-claude',
      apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
      baseUrl: 'https://proxy.example.com',
      enabledTools: const [AppProviderTool.claude],
    );

    final settings = generator.buildClaudeSettings(provider);
    final env = settings['env'] as Map;
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-claude');
    expect(env, isNot(contains('ANTHROPIC_API_KEY')));
  });

  test('writes files atomically without leaving temp artifacts', () async {
    final target = File(p.join(temp.path, 'nested', 'out.json'));
    await generator.writeJsonAtomic(target, {'ok': true});

    expect(await target.exists(), isTrue);
    expect(
      Directory(
        p.join(temp.path, 'nested'),
      ).listSync().whereType<File>().length,
      1,
    );
    final decoded = jsonDecode(await target.readAsString());
    expect(decoded['ok'], isTrue);
  });

  test('rejects invalid codex toml before write', () async {
    expect(generator.validateCodexToml('model_provider = [broken'), isNotNull);
  });
}
