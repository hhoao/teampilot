import '../../models/app_provider_config.dart';
import '../../repositories/app_provider_repository.dart';
import '../cli/flashskyai/provider/flashskyai_provider_mirror.dart';
import '../cli/registry/capabilities/provider_capability.dart';
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
    final cap = _cliRegistry.capability<ProviderCapability>(cli);
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
    for (final def
        in _cliRegistry.withCapability<ProviderCapability>()) {
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

    final currentById = {
      for (final provider in existing) provider.id: provider,
    };
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
      final mirrorResult = await FlashskyaiProviderMirror(
        repository: _repository,
      ).mirror(snapshot.providers);
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
}
