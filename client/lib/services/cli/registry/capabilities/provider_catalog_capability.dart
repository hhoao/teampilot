import '../../../../models/app_provider_config.dart';
import '../../../io/filesystem.dart';
import '../cli_capability.dart';

/// Providers discovered from the user's global CLI install.
class ProviderCatalogSnapshot {
  const ProviderCatalogSnapshot({
    this.providers = const [],
    this.sources = const [],
    this.mirrorToFlashskyai = false,
  });

  final List<AppProviderConfig> providers;
  final List<String> sources;

  /// When true, [ProviderImportService] mirrors new ids into the flashskyai catalog.
  final bool mirrorToFlashskyai;
}

/// Inputs for scanning live CLI config on the user's machine.
class ProviderCatalogLoadContext {
  const ProviderCatalogLoadContext({
    required this.fs,
    required this.homeDirectory,
    this.cwd = '',
    this.usePosixPaths = true,
    this.flashskyaiExecutablePath,
    this.now,
  });

  final Filesystem fs;
  final String homeDirectory;
  final String cwd;
  final bool usePosixPaths;
  final String? flashskyaiExecutablePath;

  /// Fixed timestamp for tests; defaults to UTC now in production.
  final int? now;

  int resolvedNow() =>
      now ?? DateTime.now().toUtc().millisecondsSinceEpoch;
}

/// Marks a CLI that owns a `providers/{tool}/providers.json` catalog.
abstract interface class ProviderCatalogCapability implements CliCapability {
  CliTool get catalogCli;

  /// Scans the user's global CLI install for importable provider rows.
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  );
}
