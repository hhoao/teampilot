import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/cli_effort_capability.dart';
import 'cursor_effort_catalog.dart';

final class CursorEffortCapability implements CliEffortCapability {
  const CursorEffortCapability();

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
      CursorEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) =>
      CursorEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({
    required String model,
    AppProviderConfig? provider,
  }) =>
      CursorEffortCatalog.defaultLevel;
}
