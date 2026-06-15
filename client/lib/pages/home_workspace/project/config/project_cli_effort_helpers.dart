import '../../../../models/app_provider_config.dart';
import '../../../../models/project_profile.dart';
import '../../../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

/// Personal-project CLI defaults: show when the tool exposes any effort UI.
bool projectCliShowsEffortPicker({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<CliEffortCapability>(cli);
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

// TODO: migrate to presets — profile.effortsByTool / profile.cli / agent.effort removed
String projectCliEffortId(ProjectProfile profile, CliTool cli) {
  return '';
}

List<String> projectCliEffortCandidates({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return const [];
  return capability.effortCandidates(model: model, provider: provider);
}

String projectCliDefaultEffort({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return '';
  return capability.defaultEffort(model: model, provider: provider);
}
