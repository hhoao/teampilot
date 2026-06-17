import '../../../../models/team_config.dart';
import '../../../provider/flashskyai/flashskyai_live_import.dart';
import 'provider_catalog_capability.dart';

final class FlashskyaiProviderCatalogCapability
    implements ProviderCatalogCapability {
  const FlashskyaiProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.flashskyai;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) =>
      FlashskyaiLiveImport.loadSnapshot(context);
}
