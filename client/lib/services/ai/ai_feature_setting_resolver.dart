import '../../cubits/app_provider_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_feature_setting.dart';
import '../../models/app_provider_config.dart';
import '../cli/registry/capabilities/provider_catalog_capability.dart';
import '../cli/registry/capabilities/provider_model_capability.dart';
import '../cli/registry/cli_display_name.dart';
import '../cli/registry/cli_tool_registry.dart';

/// Resolves the effective [AiFeatureSetting] for a feature, filling in CLI,
/// provider, and model from stored prefs and global provider defaults.
AiFeatureSetting resolveAiFeatureSetting({
  required AiFeatureSetting? stored,
  required AppProviderState appProviders,
  required CliToolRegistry registry,
  CliTool defaultCli = CliTool.claude,
}) {
  final cli = stored?.cli ?? defaultCli;
  final catalogCli = _catalogCli(registry, cli);
  final providers = catalogCli == null
      ? const <AppProviderConfig>[]
      : appProviders.providersFor(catalogCli);

  final storedProviderId = stored?.providerId.trim() ?? '';
  final providerId = storedProviderId.isNotEmpty &&
          providers.any((p) => p.id == storedProviderId)
      ? storedProviderId
      : _defaultProviderId(appProviders, catalogCli ?? cli, providers);

  final provider = providers.where((p) => p.id == providerId).firstOrNull;
  final modelCap = registry.capability<ProviderModelCapability>(cli);
  final storedModel = stored?.model.trim() ?? '';
  final model = storedModel.isNotEmpty
      ? storedModel
      : (modelCap?.defaultModel(provider: provider, providerId: providerId) ??
            '');

  return AiFeatureSetting(
    cli: cli,
    providerId: providerId,
    model: model,
    effort: stored?.effort ?? '',
  );
}

CliTool? _catalogCli(CliToolRegistry registry, CliTool cli) {
  return registry.capability<ProviderCatalogCapability>(cli) != null ? cli : null;
}

String _defaultProviderId(
  AppProviderState appProviders,
  CliTool cli,
  List<AppProviderConfig> providers,
) {
  final global = appProviders.selectedProviderIdByCli[cli];
  if (global != null && providers.any((p) => p.id == global)) {
    return global;
  }
  return providers.firstOrNull?.id ?? '';
}

/// Provider list for [cli] when a catalog exists; empty otherwise.
List<AppProviderConfig> aiFeatureProvidersForCli(
  CliTool cli,
  AppProviderState appProviders,
  CliToolRegistry registry,
) {
  final catalogCli = _catalogCli(registry, cli);
  if (catalogCli == null) return const [];
  return appProviders.providersFor(catalogCli);
}

/// Whether [resolved] has enough provider/model to run the feature.
bool aiFeatureIsConfigured({
  required AiFeatureSetting resolved,
  required CliToolRegistry registry,
  AppProviderConfig? provider,
}) {
  if (resolved.providerId.isEmpty) return false;

  final modelCapability = registry.capability<ProviderModelCapability>(
    resolved.cli,
  );
  if (modelCapability != null &&
      provider != null &&
      modelCapability.pickerMode(provider) == ProviderModelPickerMode.hidden) {
    return true;
  }
  return resolved.model.isNotEmpty;
}

/// Config line under the feature intro (CLI · provider · model, or hint).
String aiFeatureConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required bool configured,
  required AiFeatureSetting resolved,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
}) {
  if (!configured) return l10n.projectCliNotConfiguredHint;

  final def = registry.tryGet(resolved.cli);
  final cliLabel = def == null
      ? resolved.cli.value
      : cliDisplayName(def, l10n);
  final providerName = provider?.name.trim() ?? '';
  final modelLabel = resolved.model.trim();
  final effortLabel = resolved.effort.trim();

  if (providerName.isEmpty) return cliLabel;
  if (modelLabel.isEmpty && hidesModelPicker) {
    if (effortLabel.isEmpty) return '$cliLabel · $providerName';
    return '$cliLabel · $providerName · $effortLabel';
  }
  if (modelLabel.isEmpty) {
    if (effortLabel.isEmpty) return '$cliLabel · $providerName';
    return '$cliLabel · $providerName · $effortLabel';
  }
  if (effortLabel.isEmpty) {
    return l10n.aiFeatureConfigSummary(cliLabel, providerName, modelLabel);
  }
  return '${l10n.aiFeatureConfigSummary(cliLabel, providerName, modelLabel)} · $effortLabel';
}
