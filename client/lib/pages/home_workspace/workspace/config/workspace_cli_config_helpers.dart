import '../../../../models/app_provider_config.dart';
import '../../../../models/personal_profile.dart';
import '../../../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

bool workspaceCliSupportsProviderCatalog(
  CliTool cli,
  CliToolRegistry registry,
) =>
    registry.capability<ProviderCatalogCapability>(cli) != null;

String workspaceCliProviderId(PersonalProfile personal, CliTool cli) {
  return personal.providerIdsByTool[cli.value]?.trim() ?? '';
}

String workspaceCliModelId(PersonalProfile personal, CliTool cli) {
  return personal.modelsByTool[cli.value]?.trim() ?? '';
}

bool workspaceCliIsConfigured(
  PersonalProfile personal,
  CliTool cli,
  CliToolRegistry registry, {
  AppProviderConfig? selectedProvider,
  bool supportsProviderCatalog = true,
}) {
  if (!supportsProviderCatalog) return true;
  final providerId = workspaceCliProviderId(personal, cli);
  if (providerId.isEmpty) return false;

  final modelCapability = registry.capability<ProviderModelCapability>(cli);
  if (modelCapability != null &&
      selectedProvider != null &&
      modelCapability.pickerMode(selectedProvider) ==
          ProviderModelPickerMode.hidden) {
    return true;
  }
  return workspaceCliModelId(personal, cli).isNotEmpty;
}

AppProviderConfig? workspaceCliSelectedProvider(
  PersonalProfile personal,
  CliTool cli,
  Iterable<AppProviderConfig> providers,
) {
  final id = workspaceCliProviderId(personal, cli);
  if (id.isEmpty) return null;
  for (final provider in providers) {
    if (provider.id == id) return provider;
  }
  return null;
}

List<String> workspaceCliModelCandidates({
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

String workspaceCliDefaultModelForProvider(
  CliToolRegistry registry,
  CliTool cli,
  AppProviderConfig? provider, {
  required String providerId,
}) {
  final capability = registry.capability<ProviderModelCapability>(cli);
  if (capability == null) return '';
  return capability.defaultModel(provider: provider, providerId: providerId);
}

bool workspaceCliHidesModelPicker(
  CliToolRegistry registry,
  CliTool cli,
  AppProviderConfig? provider,
) {
  if (provider == null) return true;
  final capability = registry.capability<ProviderModelCapability>(cli);
  if (capability == null) return true;
  return capability.pickerMode(provider) == ProviderModelPickerMode.hidden;
}
