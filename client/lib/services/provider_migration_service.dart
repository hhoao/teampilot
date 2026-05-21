import '../repositories/app_provider_repository.dart';
import '../models/app_provider_config.dart';
import 'provider_import_service.dart';

/// One-time silent import of CLI provider configs into TeamPilot catalogs.
class ProviderMigrationService {
  ProviderMigrationService({
    AppProviderRepository? providerRepository,
    String? cliExecutablePath,
  }) : _importService = ProviderImportService(
         repository: providerRepository ?? AppProviderRepository(),
         flashskyaiExecutablePath: cliExecutablePath,
       );

  final ProviderImportService _importService;

  Future<bool> migrateIfNeeded() async {
    var changed = false;
    for (final cli in AppProviderCli.values) {
      final result = await _importService.importForCli(
        cli,
        onlyIfEmpty: true,
      );
      changed = changed || result.changed;
    }
    return changed;
  }
}
