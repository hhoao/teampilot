import '../../../../models/team_config.dart';
import '../../../provider/codex/codex_live_import.dart';
import 'provider_catalog_capability.dart';

final class CodexProviderCatalogCapability implements ProviderCatalogCapability {
  const CodexProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.codex;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) =>
      CodexLiveImport.loadSnapshot(context);
}
