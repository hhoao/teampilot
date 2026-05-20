import '../repositories/app_provider_repository.dart';
import 'tool_config_generator.dart';

/// Legacy provider migration is intentionally disabled for the single-CLI
/// provider catalog. Old `providers/providers.json` and legacy FlashskyAI
/// imports are ignored in this version.
class ProviderMigrationService {
  ProviderMigrationService({
    AppProviderRepository? providerRepository,
    String? appDataBasePath,
    String? homeDirectory,
    String? currentDirectory,
    String? cliExecutablePath,
    ToolConfigGenerator? generator,
  });

  Future<bool> migrateIfNeeded() async => false;
}
