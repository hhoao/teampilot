import 'dart:convert';
import 'package:toml/toml.dart';
import '../../models/app_provider_config.dart';
import '../../models/llm_config.dart';
import '../cli/registry/capabilities/provider_model_capability.dart';
import '../storage/app_storage.dart';
import '../io/filesystem.dart';

class ToolConfigGenerator {
  const ToolConfigGenerator();

  LlmConfig buildFlashskyaiLlmConfig(AppProviderConfig provider) {
    final config = provider.config;
    final type = config['type']?.toString() ?? 'api';
    final providerType = config['provider_type']?.toString() ?? 'openai';
    final accounts = _stringListFromConfig(config['account']);

    final providerEntry = LlmProviderConfig(
      name: provider.name,
      type: type,
      providerType: providerType,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      proxy: config['proxy'] as bool? ?? false,
      proxyUrl: config['proxy_url']?.toString() ?? '',
      accounts: accounts,
      unknownFields: {
        for (final entry in config.entries)
          if (!{
            'type',
            'provider_type',
            'proxy',
            'proxy_url',
            'account',
            'models',
          }.contains(entry.key))
            entry.key: entry.value,
      },
    );

    final models = <String, LlmModelConfig>{};
    final rawModels = config['models'];
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        models[entry.key as String] = LlmModelConfig.fromJson(
          entry.key as String,
          Map<String, Object?>.from(entry.value as Map),
        );
      }
    }
    if (models.isEmpty && provider.defaultModel.trim().isNotEmpty) {
      final modelId = '${provider.id}-default';
      models[modelId] = LlmModelConfig(
        id: modelId,
        name: provider.defaultModel,
        provider: provider.id,
        model: provider.defaultModel,
        enabled: true,
      );
    }

    return LlmConfig(providers: {provider.id: providerEntry}, models: models);
  }

  Map<String, Object?> buildCodexAuth(AppProviderConfig provider) {
    final config = provider.config;
    final rawAuth = config['auth'];
    final fromTool = rawAuth is Map
        ? Map<String, Object?>.from(rawAuth)
        : {
            for (final entry in config.entries)
              if (!_codexConfigOnlyKeys.contains(entry.key))
                entry.key: entry.value,
          };
    if (provider.apiKey.isNotEmpty) {
      fromTool['OPENAI_API_KEY'] = provider.apiKey;
    }
    return fromTool;
  }

  String buildCodexConfigToml(
    AppProviderConfig provider, {
    String? existingConfigToml,
  }) {
    final config = provider.config;
    final explicit =
        config['configToml']?.toString() ?? config['config_toml']?.toString();
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit;
    }

    final modelProvider = _resolveCodexModelProvider(
      provider,
      existingConfigToml: existingConfigToml,
    );
    final model = provider.defaultModel.trim().isNotEmpty
        ? provider.defaultModel.trim()
        : (config['model']?.toString() ?? 'gpt-5.4');
    final baseUrl = provider.baseUrl.trim().isNotEmpty
        ? provider.baseUrl.trim()
        : (config['base_url']?.toString() ?? '');
    final wireApi = config['wire_api']?.toString() ?? 'responses';

    if (baseUrl.isEmpty) {
      return existingConfigToml?.trim() ?? '';
    }

    final effort =
        provider.config['model_reasoning_effort']?.toString().trim() ?? 'high';

    return '''
model_provider = "$modelProvider"
model = "$model"
model_reasoning_effort = "$effort"
disable_response_storage = true

[model_providers.$modelProvider]
name = "$modelProvider"
base_url = "$baseUrl"
wire_api = "$wireApi"
requires_openai_auth = true
'''
        .trim();
  }

  /// Materializes Claude's `settings.json` purely from the provider's canonical
  /// fields. It emits only `env`: endpoint/credential/model are derived
  /// authoritatively from [AppProviderConfig.baseUrl] / `apiKey` /
  /// `defaultModel`, never read back from a frozen `config`. Policy concerns
  /// (permissions, hooks, enabled plugins, teammateMode, effort) are owned by
  /// the team / project / plugin scopes and merged in by the config-profile
  /// layer — this never copies them off the provider record.
  Map<String, Object?> buildClaudeSettings(AppProviderConfig provider) {
    final env = <String, String>{};
    // Custom, non-derived env keys a user added (e.g. DISABLE_AUTOUPDATER) are
    // preserved; the derived keys below are then written authoritatively.
    final rawEnv = provider.config['env'];
    if (rawEnv is Map) {
      for (final entry in rawEnv.entries) {
        env[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    if (provider.apiKey.isNotEmpty) {
      env[_claudeApiKeyField(provider)] = provider.apiKey;
    }
    if (provider.baseUrl.isNotEmpty) {
      env['ANTHROPIC_BASE_URL'] = provider.baseUrl;
    }
    final model = provider.defaultModel.trim();
    if (model.isNotEmpty) {
      env['ANTHROPIC_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = model;
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = model;
      // A model flagged as the background tier drives the cheap/fast (haiku)
      // tier; else it collapses to [model] so a single-model third-party
      // endpoint never targets a missing model.
      final background = backgroundModelFromProvider(provider);
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = background.isNotEmpty
          ? background
          : (env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] ?? model);
    }
    env.putIfAbsent('CCGUI_CLI_LOGIN_AUTHORIZED', () => '1');
    env.putIfAbsent('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC', () => '1');
    return {'env': env};
  }

  static const _codexConfigOnlyKeys = {
    'auth_mode',
    'base_url',
    'config',
    'configToml',
    'config_toml',
    'upstreamConfigToml',
    'upstream_config_toml',
    'disable_response_storage',
    'model',
    'model_provider',
    'model_reasoning_effort',
    'name',
    'requires_openai_auth',
    'wire_api',
  };

  String _claudeApiKeyField(AppProviderConfig provider) {
    final field = provider.apiKeyField.trim();
    return field == 'ANTHROPIC_AUTH_TOKEN' ? field : 'ANTHROPIC_API_KEY';
  }

  String? validateCodexToml(String toml) {
    final trimmed = toml.trim();
    if (trimmed.isEmpty) return null;
    try {
      TomlDocument.parse(trimmed);
      return null;
    } on TomlException catch (e) {
      return e.message;
    } on Object catch (e) {
      return e.toString();
    }
  }

  Future<void> writeJsonAtomic(
    String path,
    Map<String, Object?> json, {
    Filesystem? fs,
  }) async {
    final body = const JsonEncoder.withIndent('  ').convert(json);
    await writeTextAtomic(path, body, fs: fs);
  }

  Future<void> writeTextAtomic(
    String path,
    String body, {
    Filesystem? fs,
  }) async {
    final store = fs ?? AppStorage.fs;
    await store.atomicWrite(path, body);
  }

  String _resolveCodexModelProvider(
    AppProviderConfig provider, {
    String? existingConfigToml,
  }) {
    final existing = existingConfigToml?.trim() ?? '';
    if (existing.isNotEmpty) {
      final match = RegExp(
        r'^\s*model_provider\s*=\s*"([^"]+)"',
        multiLine: true,
      ).firstMatch(existing);
      if (match != null) {
        return match.group(1)!;
      }
    }
    return _slugProviderId(provider.id);
  }

  String _slugProviderId(String id) {
    return id
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  List<String> _stringListFromConfig(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
}
