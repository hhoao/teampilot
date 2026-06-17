import 'dart:convert';

import '../../../models/app_provider_config.dart';
import '../../../models/provider_presets/opencode_provider_presets.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import '../../io/filesystem.dart';
import '../codex/codex_cc_switch_import.dart';
import 'opencode_auth_artifacts.dart';
import 'opencode_data_layout.dart';

/// Scans the user's global OpenCode config and auth store.
abstract final class OpencodeLiveImport {
  OpencodeLiveImport._();

  static const _layout = OpencodeDataLayout();

  static Future<ProviderCatalogSnapshot> loadSnapshot(
    ProviderCatalogLoadContext context,
  ) async {
    final home = context.homeDirectory.trim();
    if (home.isEmpty) return const ProviderCatalogSnapshot();

    final authPath = _layout.authJsonPath(_layout.globalDataHome(home));
    final authRaw = await context.fs.readString(authPath);
    if (authRaw == null || authRaw.trim().isEmpty) {
      return const ProviderCatalogSnapshot();
    }

    Map<String, Object?> auth;
    try {
      final decoded = jsonDecode(authRaw);
      if (decoded is! Map) return const ProviderCatalogSnapshot();
      auth = decoded.cast<String, Object?>();
    } on Object {
      return const ProviderCatalogSnapshot();
    }

    final opencodeConfig = await _loadOpencodeConfig(context.fs, home);
    final now = context.resolvedNow();
    final providers = <AppProviderConfig>[];
    for (final entry in auth.entries) {
      final id = sanitizeImportedProviderId(entry.key);
      if (id.isEmpty) continue;
      if (!OpencodeAuthArtifacts.entryIndicatesReady(auth, id)) continue;
      providers.add(
        _providerFromAuthEntry(
          id: id,
          entry: entry.value,
          opencodeConfig: opencodeConfig,
          now: now,
        ),
      );
    }
    if (providers.isEmpty) return const ProviderCatalogSnapshot();
    return ProviderCatalogSnapshot(
      providers: providers,
      sources: const ['live'],
    );
  }

  static Future<Map<String, Object?>> _loadOpencodeConfig(
    Filesystem fs,
    String home,
  ) async {
    final configPath = _layout.opencodeConfigPath(
      _layout.globalConfigHome(home),
    );
    final raw = await fs.readString(configPath);
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.cast<String, Object?>();
    } on Object {
      return const {};
    }
  }

  static AppProviderConfig _providerFromAuthEntry({
    required String id,
    required Object? entry,
    required Map<String, Object?> opencodeConfig,
    required int now,
  }) {
    final preset = OpencodeProviderPresets.byId(id);
    final providerConfig = _providerConfigSection(opencodeConfig, id);
    final baseUrl = _readBaseUrl(providerConfig);
    final defaultModel = _defaultModelForProvider(id, opencodeConfig);
    final config = _buildConfig(providerConfig, preset?.template.config ?? const {});

    if (preset != null) {
      return preset.template.copyWith(
        baseUrl: baseUrl.isNotEmpty ? baseUrl : preset.template.baseUrl,
        defaultModel:
            defaultModel.isNotEmpty ? defaultModel : preset.template.defaultModel,
        config: config,
        createdAt: now,
        updatedAt: now,
      );
    }

    final authMap = entry is Map ? entry.cast<String, Object?>() : const {};
    final type = authMap['type']?.toString().trim() ?? '';
    return AppProviderConfig(
      id: id,
      cli: CliTool.opencode,
      name: _readProviderName(providerConfig, id),
      category: type == 'oauth'
          ? AppProviderCategory.official
          : AppProviderCategory.custom,
      baseUrl: baseUrl,
      defaultModel: defaultModel,
      isOfficial: type == 'oauth',
      config: config,
      createdAt: now,
      updatedAt: now,
    );
  }

  static Map<String, Object?> _providerConfigSection(
    Map<String, Object?> opencodeConfig,
    String id,
  ) {
    final providers = opencodeConfig['provider'];
    if (providers is! Map) return const {};
    final entry = providers[id];
    if (entry is! Map) return const {};
    return entry.cast<String, Object?>();
  }

  static String _readProviderName(Map<String, Object?> providerConfig, String id) {
    final name = providerConfig['name']?.toString().trim() ?? '';
    return name.isNotEmpty ? name : id;
  }

  static String _readBaseUrl(Map<String, Object?> providerConfig) {
    final options = providerConfig['options'];
    if (options is! Map) return '';
    final map = options.cast<String, Object?>();
    return (map['baseURL'] ?? map['baseUrl'] ?? '').toString().trim();
  }

  static String _defaultModelForProvider(
    String providerId,
    Map<String, Object?> opencodeConfig,
  ) {
    final model = opencodeConfig['model']?.toString().trim() ?? '';
    if (!model.contains('/')) return '';
    final slash = model.indexOf('/');
    final provider = model.substring(0, slash).trim();
    if (provider != providerId) return '';
    return model.substring(slash + 1).trim();
  }

  static Map<String, Object?> _buildConfig(
    Map<String, Object?> providerConfig,
    Map<String, Object?> presetConfig,
  ) {
    final config = <String, Object?>{...presetConfig};
    final npm = providerConfig['npm']?.toString().trim() ?? '';
    if (npm.isNotEmpty) config['npm'] = npm;
    return config;
  }
}
