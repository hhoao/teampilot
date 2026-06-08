import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/cli_effort_capability.dart';
import 'codex_effort_catalog.dart';

final class CodexEffortCapability implements CliEffortCapability {
  const CodexEffortCapability();

  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.team;

  @override
  EffortPickerPlacement memberPickerPlacement({
    AppProviderConfig? provider,
  }) =>
      EffortPickerPlacement.member;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      CodexEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) =>
      CodexEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({
    required String model,
    AppProviderConfig? provider,
  }) {
    final fromProvider =
        provider?.config['model_reasoning_effort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return CodexEffortCatalog.defaultLevel;
  }
}
