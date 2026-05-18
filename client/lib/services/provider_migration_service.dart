import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_provider_config.dart';
import '../models/llm_config.dart';
import '../repositories/app_provider_repository.dart';
import '../repositories/llm_config_repository.dart';
import 'app_storage.dart';
import 'llm_config_path_resolver.dart';
import 'tool_config_generator.dart';

/// One-time import of legacy FlashskyAI `llm_config.json` into app providers
/// and `config-profiles/common/flashskyai/llm_config.json`.
class ProviderMigrationService {
  ProviderMigrationService({
    AppProviderRepository? providerRepository,
    String? appDataBasePath,
    String? homeDirectory,
    String? currentDirectory,
    String? cliExecutablePath,
    ToolConfigGenerator? generator,
  }) : _basePath = appDataBasePath ?? AppStorage.basePath,
       _providerRepository =
           providerRepository ??
           AppProviderRepository(
             providersFile: AppProviderRepository.providersFileForBasePath(
               appDataBasePath ?? AppStorage.basePath,
             ),
             generator: generator,
           ),
       _generator = generator ?? const ToolConfigGenerator(),
       _homeDirectory = homeDirectory,
       _currentDirectory = currentDirectory ?? Directory.current.path,
       _cliExecutablePath = cliExecutablePath;

  final String _basePath;
  final AppProviderRepository _providerRepository;
  final ToolConfigGenerator _generator;
  final String? _homeDirectory;
  final String _currentDirectory;
  final String? _cliExecutablePath;

  String get _commonLlmConfigFile => p.join(
    _basePath,
    'config-profiles',
    'common',
    'flashskyai',
    'llm_config.json',
  );

  Future<bool> migrateIfNeeded() async {
    final existing = await _providerRepository.loadProviders();
    if (existing.isNotEmpty) return false;

    final legacyPath = _resolveLegacyLlmConfigPath();
    if (legacyPath == null || legacyPath.isEmpty) return false;

    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return false;

    final llm = await LlmConfigRepository(legacyFile).load();
    if (llm.providers.isEmpty) return false;

    await _importCommonLlmConfig(legacyFile, llm);

    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final migrated = <AppProviderConfig>[];

    for (final entry in llm.providers.entries) {
      final legacy = entry.value;
      final defaultModel = llm.models.values
          .where((m) => m.provider == entry.key && m.enabled)
          .map((m) => m.model)
          .cast<String?>()
          .firstWhere((m) => m != null && m.isNotEmpty, orElse: () => null);

      migrated.add(
        AppProviderConfig(
          id: entry.key,
          name: legacy.name.isNotEmpty ? legacy.name : entry.key,
          category: legacy.type == 'account'
              ? AppProviderCategory.official
              : AppProviderCategory.thirdParty,
          apiKey: legacy.apiKey,
          baseUrl: legacy.baseUrl,
          defaultModel: defaultModel ?? '',
          enabledTools: const [AppProviderTool.flashskyai],
          toolConfigs: AppProviderToolConfigs(
            flashskyai: AppProviderToolConfigPayload(
              unknownFields: {
                'type': legacy.type,
                'provider_type': legacy.providerType,
                if (legacy.proxy) 'proxy': true,
                if (legacy.proxyUrl.isNotEmpty) 'proxy_url': legacy.proxyUrl,
                ...legacy.unknownFields,
                if (llm.models.isNotEmpty)
                  'models': {
                    for (final model in llm.models.entries)
                      if (model.value.provider == entry.key)
                        model.key: model.value.toJson(),
                  },
              },
            ),
          ),
          createdAt: now,
          updatedAt: now,
          unknownFields: const {},
        ),
      );
    }

    await _providerRepository.saveProviders(migrated);
    return true;
  }

  Future<void> _importCommonLlmConfig(File legacyFile, LlmConfig llm) async {
    final target = File(_commonLlmConfigFile);
    await target.parent.create(recursive: true);
    if (target.path != legacyFile.path) {
      await legacyFile.copy(target.path);
      return;
    }
    await _generator.writeJsonAtomic(target, llm.toJson());
  }

  String? _resolveLegacyLlmConfigPath() {
    final resolved = resolveLlmConfigPath(
      userOverride: null,
      currentDirectory: _currentDirectory,
      homeDirectory: _homeDirectory,
      cliExecutablePath: _cliExecutablePath,
    );
    if (resolved.path.isNotEmpty) return resolved.path;

    final home = _homeDirectory?.trim() ?? '';
    if (home.isEmpty) return null;
    final candidate = p.join(home, '.flashskyai', 'llm_config.json');
    return File(candidate).existsSync() ? candidate : null;
  }
}
