import '../../../../models/app_provider_config.dart';
import '../../../../models/project_profile.dart';
import '../../../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

bool projectCliSupportsProviderCatalog(
  CliTool cli,
  CliToolRegistry registry,
) =>
    registry.capability<ProviderCatalogCapability>(cli) != null;

// TODO: migrate to presets — profile.providerIdsByTool / profile.cli / agent.provider removed
String projectCliProviderId(ProjectProfile profile, CliTool cli) {
  return '';
}

// TODO: migrate to presets — profile.modelsByTool / profile.cli / agent.model removed
String projectCliModelId(ProjectProfile profile, CliTool cli) {
  return '';
}

bool projectCliIsConfigured(
  ProjectProfile profile,
  CliTool cli,
  CliToolRegistry registry, {
  AppProviderConfig? selectedProvider,
  bool supportsProviderCatalog = true,
}) {
  if (!supportsProviderCatalog) return true;
  final providerId = projectCliProviderId(profile, cli);
  if (providerId.isEmpty) return false;

  final modelCapability = registry.capability<ProviderModelCapability>(cli);
  if (modelCapability != null &&
      selectedProvider != null &&
      modelCapability.pickerMode(selectedProvider) ==
          ProviderModelPickerMode.hidden) {
    return true;
  }
  return projectCliModelId(profile, cli).isNotEmpty;
}

AppProviderConfig? projectCliSelectedProvider(
  ProjectProfile profile,
  CliTool cli,
  Iterable<AppProviderConfig> providers,
) {
  final id = projectCliProviderId(profile, cli);
  if (id.isEmpty) return null;
  for (final provider in providers) {
    if (provider.id == id) return provider;
  }
  return null;
}

List<String> projectCliModelCandidates({
  required CliToolRegistry registry,
  required CliTool cli,
  required String providerId,
  required AppProviderConfig? appProvider,
  required String currentModel,
}) {
  final capability = registry.capability<ProviderModelCapability>(cli);
  if (capability == null) return const [];
  return capability.modelCandidates(
    provider: appProvider,
    providerId: providerId,
    currentModel: currentModel,
  );
}

String projectCliDefaultModelForProvider(
  CliToolRegistry registry,
  CliTool cli,
  AppProviderConfig? provider, {
  required String providerId,
}) {
  final capability = registry.capability<ProviderModelCapability>(cli);
  if (capability == null) return '';
  return capability.defaultModel(provider: provider, providerId: providerId);
}

bool projectCliHidesModelPicker(
  CliToolRegistry registry,
  CliTool cli,
  AppProviderConfig? provider,
) {
  if (provider == null) return true;
  final capability = registry.capability<ProviderModelCapability>(cli);
  if (capability == null) return true;
  return capability.pickerMode(provider) == ProviderModelPickerMode.hidden;
}
