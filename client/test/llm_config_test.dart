import 'dart:convert';
import 'dart:io';

import 'package:flashskyai_client/llm_config.dart';
import 'package:flashskyai_client/llm_config_controller.dart';
import 'package:flashskyai_client/llm_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rawConfig = {
    'providers': {
      'OpenRoute': {
        'type': 'api',
        'provider_type': 'openai',
        'base_url': 'https://openrouter.ai/api/v1/',
        'api_key': '',
        'proxy': true,
        'proxy_url': 'http://127.0.0.1:8118',
        'unknown_provider_field': 'keep-me',
      },
      'DeepSeek': {
        'type': 'api',
        'provider_type': 'openai',
        'base_url': 'https://api.deepseek.com',
        'api_key': 'sk-secret',
        'proxy': false,
      },
      'Codex': {
        'type': 'account',
        'account': ['~/.codex/auth.json'],
        'proxy': false,
      },
    },
    'models': {
      'gpt': {
        'name': 'gpt',
        'provider': 'OpenRoute',
        'model': 'openai/gpt-5.2',
        'enabled': true,
      },
      'ghost': {
        'name': 'ghost',
        'provider': 'Missing',
        'model': 'ghost-model',
        'enabled': true,
      },
    },
    'unknown_root_field': 'keep-root',
  };

  test('parses providers and models while preserving unknown fields', () {
    final config = LlmConfig.fromJson(rawConfig);

    expect(config.providers, hasLength(3));
    expect(config.models, hasLength(2));
    expect(config.providers['OpenRoute']?.providerType, 'openai');
    expect(config.providers['Codex']?.accounts, ['~/.codex/auth.json']);
    expect(
      config.providers['OpenRoute']?.unknownFields['unknown_provider_field'],
      'keep-me',
    );
    expect(config.unknownFields['unknown_root_field'], 'keep-root');
  });

  test('validates missing providers and empty api keys', () {
    final config = LlmConfig.fromJson(rawConfig);

    expect(config.validationMessages, contains('OpenRoute API key is empty.'));
    expect(
      config.validationMessages,
      contains('ghost references missing provider Missing.'),
    );
  });

  test('masks secrets in json preview', () {
    final config = LlmConfig.fromJson(rawConfig);
    final masked = config.toMaskedJson();

    expect(masked['providers']['DeepSeek']['api_key'], LlmConfig.maskedSecret);
    expect(masked['providers']['OpenRoute']['api_key'], '');
  });

  test(
    'repository preserves existing secret when saving masked placeholder',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'llm-config-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/llm_config.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rawConfig),
      );
      final repository = LlmConfigRepository(file);
      final loaded = await repository.load();
      final edited = loaded.copyWith(
        providers: {
          ...loaded.providers,
          'DeepSeek': loaded.providers['DeepSeek']!.copyWith(
            apiKey: LlmConfig.maskedSecret,
            baseUrl: 'https://api.deepseek.com/v2',
          ),
        },
      );

      await repository.save(edited, previous: loaded);

      final saved =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final providers = saved['providers'] as Map<String, Object?>;
      final deepSeek = providers['DeepSeek'] as Map<String, Object?>;
      expect(deepSeek['api_key'], 'sk-secret');
      expect(deepSeek['base_url'], 'https://api.deepseek.com/v2');
      expect(saved['unknown_root_field'], 'keep-root');
    },
  );

  group('LlmConfigController mutations', () {
    late LlmConfigController controller;

    setUp(() {
      controller = LlmConfigController(
        initialConfig: LlmConfig.fromJson(rawConfig),
      );
    });

    test('addProvider adds a new provider', () {
      controller.addProvider(
        const LlmProviderConfig(
          name: 'NewProvider',
          type: 'api',
          providerType: 'openai',
          baseUrl: 'https://api.example.com',
        ),
      );

      expect(controller.config.providers.containsKey('NewProvider'), isTrue);
      expect(
        controller.config.providers['NewProvider']!.baseUrl,
        'https://api.example.com',
      );
    });

    test('updateProvider updates an existing provider', () {
      controller.updateProvider(
        'OpenRoute',
        controller.config.providers['OpenRoute']!.copyWith(
          baseUrl: 'https://openrouter.ai/api/v2/',
        ),
      );

      expect(
        controller.config.providers['OpenRoute']!.baseUrl,
        'https://openrouter.ai/api/v2/',
      );
    });

    test('deleteProvider removes a provider', () {
      controller.deleteProvider('OpenRoute');

      expect(controller.config.providers.containsKey('OpenRoute'), isFalse);
      expect(controller.config.providers.length, 2); // was 3, now 2
    });

    test('addModel adds a new model', () {
      controller.addModel(
        const LlmModelConfig(
          id: 'new-model',
          name: 'New Model',
          provider: 'DeepSeek',
          model: 'new-model-v1',
          enabled: true,
        ),
      );

      expect(controller.config.models.containsKey('new-model'), isTrue);
      expect(controller.config.models['new-model']!.provider, 'DeepSeek');
    });

    test('updateModel updates an existing model', () {
      controller.updateModel(
        'gpt',
        controller.config.models['gpt']!.copyWith(model: 'openai/gpt-5.3'),
      );

      expect(
        controller.config.models['gpt']!.model,
        'openai/gpt-5.3',
      );
    });

    test('deleteModel removes a model', () {
      controller.deleteModel('gpt');

      expect(controller.config.models.containsKey('gpt'), isFalse);
      expect(controller.config.models.length, 1); // was 2, now 1
    });

    test('revealApiKey returns the actual key', () {
      final key = controller.revealApiKey('DeepSeek');

      expect(key, 'sk-secret');
    });

    test('revealApiKey returns empty string for missing provider', () {
      final key = controller.revealApiKey('DoesNotExist');

      expect(key, '');
    });
  });
}
