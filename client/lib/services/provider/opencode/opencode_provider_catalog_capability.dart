import '../../../../models/team_config.dart';
import '../../cli/registry/capabilities/provider_catalog_capability.dart';
import 'opencode_live_import.dart';

final class OpencodeProviderCatalogCapability
    implements ProviderCatalogCapability {
  const OpencodeProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.opencode;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) =>
      OpencodeLiveImport.loadSnapshot(context);
}
