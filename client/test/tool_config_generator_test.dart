import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/runtime_storage_context.dart';
import 'package:teampilot/services/tool_config_generator.dart';

void main() {
  late ToolConfigGenerator generator;
  late Directory temp;

  setUp(() async {
    generator = const ToolConfigGenerator();
    temp = await Directory.systemTemp.createTemp('tool_cfg_gen_');
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(),
      paths: AppPaths(temp.path),
      home: temp.path,
      cwd: temp.path,
    );
  });

  tearDown(() async {
    RuntimeStorageContext.resetForTesting();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('builds flashskyai llm_config from flashskyai provider config', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.flashskyai,
      name: 'DeepSeek',
      apiKey: 'sk-test',
      baseUrl: 'https://api.deepseek.com',
      defaultModel: 'deepseek-chat',
      config: {'provider_type': 'openai'},
    );

    final llm = generator.buildFlashskyaiLlmConfig(provider);
    expect(llm.providers['deepseek']?.baseUrl, 'https://api.deepseek.com');
    expect(llm.providers['deepseek']?.apiKey, 'sk-test');
    expect(llm.providers['deepseek']?.providerType, 'openai');
    expect(llm.models['deepseek-default']?.model, 'deepseek-chat');
  });

  test('builds codex auth and config.toml for codex provider', () {
    const provider = AppProviderConfig(
      id: 'My Provider',
      cli: AppProviderCli.codex,
      name: 'My Provider',
      apiKey: 'codex-key',
      baseUrl: 'https://api.example.com/v1',
      defaultModel: 'gpt-5.4',
      category: AppProviderCategory.thirdParty,
    );

    final auth = generator.buildCodexAuth(provider);
    expect(auth['OPENAI_API_KEY'], 'codex-key');

    final toml = generator.buildCodexConfigToml(provider);
    expect(generator.validateCodexToml(toml), isNull);
    expect(toml, contains('model_provider = "my_provider"'));
    expect(toml, contains('base_url = "https://api.example.com/v1"'));
  });

  test('uses explicit codex configToml and auth config when present', () {
    const provider = AppProviderConfig(
      id: 'openrouter',
      cli: AppProviderCli.codex,
      name: 'OpenRouter',
      apiKey: 'sk-openrouter',
      config: {
        'auth': {'CUSTOM_VALUE': 'kept'},
        'configToml': '''
model_provider = "openrouter"
model = "gpt-5.4"

[model_providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
wire_api = "responses"
requires_openai_auth = true
''',
      },
    );

    final auth = generator.buildCodexAuth(provider);
    expect(auth['CUSTOM_VALUE'], 'kept');
    expect(auth['OPENAI_API_KEY'], 'sk-openrouter');

    final toml = generator.buildCodexConfigToml(provider);
    expect(toml, contains('model_provider = "openrouter"'));
    expect(toml, contains('base_url = "https://openrouter.ai/api/v1"'));
  });

  test('builds claude settings.json with env overrides', () {
    const provider = AppProviderConfig(
      id: 'ds',
      cli: AppProviderCli.claude,
      name: 'DeepSeek',
      defaultModel: 'deepseek-v4-pro[1m]',
      config: {
        'env': {
          'ANTHROPIC_BASE_URL': 'https://api.deepseek.com',
          'ANTHROPIC_API_KEY': 'sk-claude',
        },
      },
    );

    final settings = generator.buildClaudeSettings(provider);
    final env = settings['env'] as Map;
    expect(env['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com');
    expect(env['ANTHROPIC_API_KEY'], 'sk-claude');
    expect(env['ANTHROPIC_MODEL'], 'deepseek-v4-pro[1m]');
    expect(env['ANTHROPIC_DEFAULT_HAIKU_MODEL'], 'deepseek-v4-pro[1m]');
    expect(env['ANTHROPIC_DEFAULT_SONNET_MODEL'], 'deepseek-v4-pro[1m]');
    expect(env['ANTHROPIC_DEFAULT_OPUS_MODEL'], 'deepseek-v4-pro[1m]');
    expect(env['CCGUI_CLI_LOGIN_AUTHORIZED'], '1');
    expect(env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'], '1');
  });

  test('uses configured claude api key field', () {
    const provider = AppProviderConfig(
      id: 'claude-proxy',
      cli: AppProviderCli.claude,
      name: 'Claude Proxy',
      apiKey: 'sk-claude',
      apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
      baseUrl: 'https://proxy.example.com',
    );

    final settings = generator.buildClaudeSettings(provider);
    final env = settings['env'] as Map;
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-claude');
    expect(env, isNot(contains('ANTHROPIC_API_KEY')));
  });

  test('top-level apiKey overrides empty ANTHROPIC_AUTH_TOKEN in config.env', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: AppProviderCli.claude,
      name: 'DeepSeek',
      apiKey: 'sk-deepseek',
      apiKeyField: 'ANTHROPIC_AUTH_TOKEN',
      config: {
        'api_key_field': 'ANTHROPIC_AUTH_TOKEN',
        'env': {
          'ANTHROPIC_AUTH_TOKEN': '',
          'ANTHROPIC_BASE_URL': 'https://api.deepseek.com/anthropic',
        },
      },
    );

    final env = generator.buildClaudeSettings(provider)['env'] as Map;
    expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-deepseek');
  });

  test('writes files atomically without leaving temp artifacts', () async {
    final target = p.join(temp.path, 'nested', 'out.json');
    await generator.writeJsonAtomic(target, {'ok': true});

    final file = File(target);
    expect(await file.exists(), isTrue);
    expect(
      Directory(
        p.join(temp.path, 'nested'),
      ).listSync().whereType<File>().length,
      1,
    );
    final decoded = jsonDecode(await file.readAsString());
    expect(decoded['ok'], isTrue);
  });

  test('rejects invalid codex toml before write', () async {
    expect(generator.validateCodexToml('model_provider = [broken'), isNotNull);
  });
}
