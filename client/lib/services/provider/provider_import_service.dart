import '../../models/app_provider_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/registry/capabilities/provider_catalog_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/app_storage.dart';

class ProviderImportResult {
  const ProviderImportResult({
    required this.cli,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.mirroredToFlashskyai = 0,
    this.mirrorSkipped = 0,
    this.sources = const [],
  });

  final CliTool cli;
  final int added;
  final int updated;
  final int skipped;
  final int mirroredToFlashskyai;
  final int mirrorSkipped;
  final List<String> sources;

  bool get changed => added > 0 || updated > 0 || mirroredToFlashskyai > 0;
}

/// Merges [ProviderCatalogSnapshot] rows into TeamPilot provider catalogs.
class ProviderImportService {
  ProviderImportService({
    AppProviderRepository? repository,
    String? flashskyaiExecutablePath,
    CliToolRegistry? cliRegistry,
    ProviderCatalogLoadContext? catalogLoadContext,
  }) : _repository = repository ?? AppProviderRepository(),
       _flashskyaiExecutablePath = flashskyaiExecutablePath,
       _cliRegistry = cliRegistry ?? CliToolRegistry.builtIn(),
       _catalogLoadContextOverride = catalogLoadContext;

  final AppProviderRepository _repository;
  final String? _flashskyaiExecutablePath;
  final CliToolRegistry _cliRegistry;
  final ProviderCatalogLoadContext? _catalogLoadContextOverride;

  ProviderCatalogLoadContext get catalogLoadContext =>
      _catalogLoadContextOverride ??
      ProviderCatalogLoadContext(
        fs: AppStorage.fs,
        homeDirectory: AppStorage.home,
        cwd: AppStorage.cwd,
        usePosixPaths: AppStorage.usesPosixPaths,
        flashskyaiExecutablePath: _flashskyaiExecutablePath,
      );

  Future<ProviderImportResult> importForCli(
    CliTool cli, {
    required bool onlyIfEmpty,
  }) async {
    final cap = _cliRegistry.capability<ProviderCatalogCapability>(cli);
    if (cap == null) {
      return ProviderImportResult(cli: cli);
    }
    final snapshot = await cap.loadFromLiveSources(catalogLoadContext);
    return applySnapshot(cli, snapshot, onlyIfEmpty: onlyIfEmpty);
  }

  Future<List<ProviderImportResult>> importAllCatalogClis({
    required bool onlyIfEmpty,
  }) async {
    final results = <ProviderImportResult>[];
    for (final def in _cliRegistry.withCapability<ProviderCatalogCapability>()) {
      results.add(await importForCli(def.id, onlyIfEmpty: onlyIfEmpty));
    }
    return results;
  }

  Future<ProviderImportResult> applySnapshot(
    CliTool cli,
    ProviderCatalogSnapshot snapshot, {
    required bool onlyIfEmpty,
  }) async {
    final existing = await _repository.loadProviders(cli);
    if (onlyIfEmpty && existing.isNotEmpty) {
      return ProviderImportResult(cli: cli, skipped: existing.length);
    }

    if (snapshot.providers.isEmpty) {
      return ProviderImportResult(cli: cli);
    }

    final currentById = {for (final provider in existing) provider.id: provider};
    var added = 0;
    var updated = 0;
    for (final provider in snapshot.providers) {
      if (currentById.containsKey(provider.id)) {
        updated++;
      } else {
        added++;
      }
      currentById[provider.id] = provider;
    }
    await _repository.saveProviders(cli, currentById.values.toList());

    var mirrored = 0;
    var mirrorSkipped = 0;
    if (snapshot.mirrorToFlashskyai) {
      final mirrorResult = await _mirrorToFlashskyai(snapshot.providers);
      mirrored = mirrorResult.added;
      mirrorSkipped = mirrorResult.skipped;
    }

    return ProviderImportResult(
      cli: cli,
      added: added,
      updated: updated,
      mirroredToFlashskyai: mirrored,
      mirrorSkipped: mirrorSkipped,
      sources: snapshot.sources,
    );
  }

  Future<_MirrorResult> _mirrorToFlashskyai(
    List<AppProviderConfig> providers,
  ) async {
    final existing = await _repository.loadProviders(CliTool.flashskyai);
    final byId = {for (final provider in existing) provider.id: provider};
    final existingModelIds = <String>{
      for (final provider in existing) ..._flashskyaiModelIds(provider),
    };
    var added = 0;
    var skipped = 0;
    for (final provider in providers) {
      final mirrored = _toFlashskyaiProvider(
        provider,
        reservedModelIds: existingModelIds,
      );
      if (mirrored == null) continue;
      if (byId.containsKey(mirrored.id)) {
        skipped++;
        continue;
      }
      existingModelIds.addAll(_flashskyaiModelIds(mirrored));
      byId[mirrored.id] = mirrored;
      added++;
    }
    if (added > 0) {
      await _repository.saveProviders(
        CliTool.flashskyai,
        byId.values.toList(),
      );
    }
    return _MirrorResult(added: added, skipped: skipped);
  }

  AppProviderConfig? _toFlashskyaiProvider(
    AppProviderConfig provider, {
    Set<String> reservedModelIds = const {},
  }) {
    if (provider.cli == CliTool.flashskyai) return null;
    if (provider.id == 'default' &&
        provider.apiKey.trim().isEmpty &&
        provider.baseUrl.trim().isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final model = provider.defaultModel.trim();
    final shouldMirrorModel =
        model.isNotEmpty && !reservedModelIds.contains(model);
    final mirroredDefaultModel = shouldMirrorModel ? model : '';
    final providerType = _providerTypeFor(provider);
    return AppProviderConfig(
      id: provider.id,
      cli: CliTool.flashskyai,
      name: provider.name,
      notes: provider.notes,
      websiteUrl: provider.websiteUrl,
      apiKeyUrl: provider.apiKeyUrl,
      category: provider.category,
      apiKey: provider.apiKey,
      apiKeyField: 'api_key',
      baseUrl: provider.baseUrl,
      defaultModel: mirroredDefaultModel,
      icon: provider.icon,
      iconColor: provider.iconColor,
      isOfficial: provider.isOfficial,
      isPartner: provider.isPartner,
      partnerPromotionKey: provider.partnerPromotionKey,
      endpointCandidates: provider.endpointCandidates,
      config: {
        'type': 'api',
        'provider_type': providerType,
        if (shouldMirrorModel)
          'models': {
            model: {
              'name': model,
              'provider': provider.id,
              'model': model,
              'enabled': true,
            },
          },
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  Set<String> _flashskyaiModelIds(AppProviderConfig provider) {
    final rawModels = provider.config['models'];
    if (rawModels is Map) {
      return rawModels.keys.map((key) => key.toString()).toSet();
    }
    final model = provider.defaultModel.trim();
    if (model.isEmpty) return const {};
    return {model};
  }

  String _providerTypeFor(AppProviderConfig provider) {
    if (provider.cli == CliTool.codex) return 'openai';
    final url = provider.baseUrl.toLowerCase();
    if (url.contains('anthropic') || url.contains('claude')) {
      return 'anthropic';
    }
    return 'openai';
  }
}

class _MirrorResult {
  const _MirrorResult({required this.added, required this.skipped});

  final int added;
  final int skipped;
}
