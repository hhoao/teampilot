import '../../../../models/team_config.dart';
import '../provider/claude_live_import.dart';
import '../../registry/capabilities/provider_catalog_capability.dart';

final class ClaudeProviderCatalogCapability
    implements ProviderCatalogCapability {
  const ClaudeProviderCatalogCapability();

  @override
  CliTool get catalogCli => CliTool.claude;

  @override
  String? get defaultOfficialProviderId => 'claude-official';
  @override
  Future<ProviderCatalogSnapshot> loadFromLiveSources(
    ProviderCatalogLoadContext context,
  ) => ClaudeLiveImport.loadSnapshot(context);
}
