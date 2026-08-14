import '../../../../models/app_provider_config.dart';
import '../../../../services/cli/registry/capabilities/provider_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

/// Show effort picker when the tool exposes any effort UI for [provider]/[model].
bool workspaceCliShowsEffortPicker({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<ProviderCapability>(cli);
  if (capability == null || provider == null) return false;
  if (capability.teamPickerPlacement() == EffortPickerPlacement.hidden &&
      capability.memberPickerPlacement(provider: provider) ==
          EffortPickerPlacement.hidden &&
      capability.providerPickerPlacement(provider) ==
          EffortPickerPlacement.hidden) {
    return false;
  }
  final resolvedModel = model.trim().isNotEmpty
      ? model.trim()
      : provider.defaultModel.trim();
  return capability.isApplicable(model: resolvedModel);
}

List<String> workspaceCliEffortCandidates({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<ProviderCapability>(cli);
  if (capability == null) return const [];
  return capability.effortCandidates(model: model, provider: provider);
}

String workspaceCliDefaultEffort({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<ProviderCapability>(cli);
  if (capability == null) return '';
  return capability.defaultEffort(model: model, provider: provider);
}
