import '../../../../models/team_config.dart';
import '../../registry/capabilities/provider_catalog_capability.dart';
import 'cursor_live_import.dart';

final class CursorProviderCatalogCapability
    implements ProviderCatalogCapability {
  const CursorProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.cursor;

  @override
  String? get defaultOfficialProviderId => 'cursor-account';
  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => CursorLiveImport.loadSnapshot(context);
}
