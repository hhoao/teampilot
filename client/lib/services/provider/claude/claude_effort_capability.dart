import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/cli_effort_capability.dart';
import 'claude_effort_catalog.dart';

final class ClaudeEffortCapability implements CliEffortCapability {
  const ClaudeEffortCapability();

  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({
    AppProviderConfig? provider,
  }) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.hidden;

  @override
  bool isApplicable({required String model}) =>
      ClaudeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) =>
      ClaudeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({
    required String model,
    AppProviderConfig? provider,
  }) =>
      ClaudeEffortCatalog.defaultLevel;
}
