import '../../../../models/app_provider_config.dart';
import '../../../../models/personal_identity.dart';
import '../../../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';

/// Personal-workspace CLI defaults: show when the tool exposes any effort UI.
bool workspaceCliShowsEffortPicker({
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

String workspaceCliEffortId(PersonalIdentity personal, CliTool cli) {
  return personal.effortsByTool[cli.value]?.trim() ?? '';
}

List<String> workspaceCliEffortCandidates({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return const [];
  return capability.effortCandidates(model: model, provider: provider);
}

String workspaceCliDefaultEffort({
  required CliToolRegistry registry,
  required CliTool cli,
  required AppProviderConfig? provider,
  required String model,
}) {
  final capability = registry.capability<CliEffortCapability>(cli);
  if (capability == null) return '';
  return capability.defaultEffort(model: model, provider: provider);
}
