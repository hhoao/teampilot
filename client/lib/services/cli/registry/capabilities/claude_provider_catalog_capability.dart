import '../../../../models/team_config.dart';
import '../../../provider/claude/claude_live_import.dart';
import 'provider_catalog_capability.dart';

final class ClaudeProviderCatalogCapability implements ProviderCatalogCapability {
  const ClaudeProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.claude;

  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) =>
      ClaudeLiveImport.loadSnapshot(context);
}
