import 'dart:convert';

import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import '../../io/filesystem.dart';
import '../llm_config_path_resolver.dart';
import '../../../models/llm_config.dart';
import '../codex/codex_cc_switch_import.dart';

/// Scans the flashskyai install `llm_config.json`.
abstract final class FlashskyaiLiveImport {
  FlashskyaiLiveImport._();

  static Future<ProviderCatalogSnapshot> loadSnapshot(
    ProviderCatalogLoadContext context,
  ) async {
    final resolved = resolveLlmConfigPath(
      userOverride: null,
      currentDirectory: context.cwd,
      homeDirectory: context.homeDirectory,
      cliExecutablePath: context.flashskyaiExecutablePath,
      usePosixPaths: context.usePosixPaths,
    );
    if (resolved.path.isEmpty) return const ProviderCatalogSnapshot();

    final llm = await _loadLlmConfig(context.fs, resolved.path);
    if (llm.providers.isEmpty) return const ProviderCatalogSnapshot();

    final now = context.resolvedNow();
    final providers = <AppProviderConfig>[];
    for (final entry in llm.providers.entries) {
      final id = sanitizeImportedProviderId(entry.key);
      if (id.isEmpty) continue;
      final source = entry.value;
      final defaultModel = llm.models.values
          .where((m) => m.provider == entry.key && m.enabled)
          .map((m) => m.model)
          .firstWhere((m) => m.trim().isNotEmpty, orElse: () => '');
      providers.add(
        AppProviderConfig(
          id: id,
          cli: CliTool.flashskyai,
          name: source.name.isNotEmpty ? source.name : id,
          category: source.type == 'account'
              ? AppProviderCategory.official
              : AppProviderCategory.thirdParty,
          apiKey: source.apiKey,
          apiKeyField: 'api_key',
          baseUrl: source.baseUrl,
          defaultModel: defaultModel,
          config: {
            'type': source.type.isNotEmpty ? source.type : 'api',
            'provider_type': source.providerType.isNotEmpty
                ? source.providerType
                : 'openai',
            if (source.proxy) 'proxy': true,
            if (source.proxyUrl.isNotEmpty) 'proxy_url': source.proxyUrl,
            if (source.accounts.isNotEmpty) 'account': source.accounts,
            ...source.unknownFields,
            if (llm.models.isNotEmpty)
              'models': {
                for (final model in llm.models.entries)
                  if (model.value.provider == entry.key)
                    model.key: {
                      ...model.value.toJson(),
                      'provider': id,
                    },
              },
          },
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return ProviderCatalogSnapshot(
      providers: providers,
      sources: const ['llm_config'],
    );
  }
}

Future<LlmConfig> _loadLlmConfig(Filesystem fs, String path) async {
  final content = await fs.readString(path);
  if (content == null || content.isEmpty) {
    return const LlmConfig();
  }
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return const LlmConfig();
    }
    return LlmConfig.fromJson(Map<String, Object?>.from(decoded));
  } on FormatException {
    return const LlmConfig();
  } on TypeError {
    return const LlmConfig();
  }
}
