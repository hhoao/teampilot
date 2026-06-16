import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_model_capability.dart';
import 'claude_model_catalog.dart';
import 'claude_official_provider.dart';

/// Claude's built-in official aliases + frontier model ids.
final class ClaudeCatalogSource implements ModelCatalogSource {
  const ClaudeCatalogSource();

  @override
  List<String> modelsFor({
    required AppProviderConfig? provider,
    required String providerId,
  }) =>
      ClaudeModelCatalog.knownModelsForProviderId(providerId, provider: provider);
}

final class ClaudeProviderModelCapability extends CatalogModelCapability {
  const ClaudeProviderModelCapability();

  @override
  bool get supportsModelTiers => true;

  @override
  List<ModelCatalogSource> get catalogSources => const [ClaudeCatalogSource()];

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.cli != CliTool.claude) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  @override
  String defaultModel({
    required AppProviderConfig? provider,
    required String providerId,
  }) {
    if (provider != null && isOfficialClaudeProvider(provider)) {
      final fromProvider = provider.defaultModel.trim();
      if (fromProvider.isNotEmpty) return fromProvider;
      return ClaudeModelCatalog.defaultOfficialAlias;
    }
    return resolveDefaultProviderModel(
      this,
      provider: provider,
      providerId: providerId,
    );
  }
}
