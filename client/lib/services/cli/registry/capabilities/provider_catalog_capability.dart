import '../../../../models/team_config.dart';
import '../../../provider/provider_import_service.dart';
import '../cli_capability.dart';

/// Marks a CLI that owns a `providers/{tool}/providers.json` catalog.
abstract interface class ProviderCatalogCapability implements CliCapability {
  CliTool get catalogCli;

  Future<ProviderImportResult> importForCli({
    required bool onlyIfEmpty,
    required ProviderImportService importService,
  });
}
