import '../../../models/app_provider_config.dart';
import '../../cli/registry/capabilities/cli_effort_capability.dart';
import 'opencode_effort_catalog.dart';

final class OpencodeEffortCapability implements CliEffortCapability {
  const OpencodeEffortCapability();

  @override
  EffortPickerPlacement teamPickerPlacement() => EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement memberPickerPlacement({
    AppProviderConfig? provider,
  }) =>
      EffortPickerPlacement.hidden;

  @override
  EffortPickerPlacement providerPickerPlacement(AppProviderConfig provider) =>
      EffortPickerPlacement.provider;

  @override
  bool isApplicable({required String model}) =>
      OpencodeEffortCatalog.modelSupportsEffort(model);

  @override
  List<String> effortCandidates({
    required String model,
    AppProviderConfig? provider,
  }) =>
      OpencodeEffortCatalog.levelsForModel(model);

  @override
  String defaultEffort({
    required String model,
    AppProviderConfig? provider,
  }) {
    final fromProvider =
        provider?.config['reasoningEffort']?.toString().trim() ?? '';
    if (fromProvider.isNotEmpty) return fromProvider;
    return OpencodeEffortCatalog.defaultLevel;
  }
}
