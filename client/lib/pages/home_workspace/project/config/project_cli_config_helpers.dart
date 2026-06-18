import '../../../../models/app_provider_config.dart';
import '../../../../models/personal_identity.dart';
import '../../../../services/cli/registry/capabilities/provider_catalog_capability.dart';
import '../../../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

bool projectCliSupportsProviderCatalog(
  CliTool cli,
  CliToolRegistry registry,
) =>
    registry.capability<ProviderCatalogCapability>(cli) != null;

String projectCliProviderId(PersonalIdentity personal, CliTool cli) {
  return personal.providerIdsByTool[cli.value]?.trim() ?? '';
}

String projectCliModelId(PersonalIdentity personal, CliTool cli) {
  return personal.modelsByTool[cli.value]?.trim() ?? '';
}

bool projectCliIsConfigured(
  PersonalIdentity personal,
  CliTool cli,
  CliToolRegistry registry, {
  AppProviderConfig? selectedProvider,
  bool supportsProviderCatalog = true,
}) {
  if (!supportsProviderCatalog) return true;
  final providerId = projectCliProviderId(personal, cli);
  if (providerId.isEmpty) return false;

  final modelCapability = registry.capability<ProviderModelCapability>(cli);
  if (modelCapability != null &&
      selectedProvider != null &&
      modelCapability.pickerMode(selectedProvider) ==
          ProviderModelPickerMode.hidden) {
    return true;
  }
  return projectCliModelId(personal, cli).isNotEmpty;
}

AppProviderConfig? projectCliSelectedProvider(
  PersonalIdentity personal,
  CliTool cli,
  Iterable<AppProviderConfig> providers,
) {
  final id = projectCliProviderId(personal, cli);
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
