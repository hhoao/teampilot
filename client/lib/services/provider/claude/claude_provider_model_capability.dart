import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/provider_model_capability.dart';
import 'claude_model_catalog.dart';
import 'claude_official_provider.dart';

final class ClaudeProviderModelCapability implements ProviderModelCapability {
  const ClaudeProviderModelCapability();

  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) {
    if (provider.cli != CliTool.claude) {
      return ProviderModelPickerMode.hidden;
    }
    return ProviderModelPickerMode.catalogWithCustomEntry;
  }

  @override
  List<String> modelCandidates({
    required AppProviderConfig? provider,
    required String providerId,
    required String currentModel,
  }) {
    final catalog = ClaudeModelCatalog.knownModelsForProviderId(
      providerId,
      provider: provider,
    );
    return mergeProviderModelCandidates(
      builtInCatalog: catalog,
      provider: provider,
      currentModel: currentModel,
    );
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
