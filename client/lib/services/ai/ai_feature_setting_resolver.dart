import '../../cubits/app_provider_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_feature_setting.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../cli/registry/capabilities/provider_catalog_capability.dart';
import '../cli/registry/capabilities/provider_model_capability.dart';
import '../cli/registry/cli_display_name.dart';
import '../cli/registry/cli_tool_registry.dart';

/// Resolves the effective [AiFeatureSetting] for a feature, filling in CLI,
/// provider, and model from stored prefs, active preset, and global defaults.
AiFeatureSetting resolveAiFeatureSetting({
  required AiFeatureSetting? stored,
  required AppProviderState appProviders,
  required CliToolRegistry registry,
  List<CliPreset> globalPresets = const [],
  CliTool defaultCli = CliTool.claude,
}) {
  final presetId = stored?.activePresetId?.trim();
  if (presetId != null && presetId.isNotEmpty) {
    CliPreset? preset;
    for (final candidate in globalPresets) {
      if (candidate.id == presetId) {
        preset = candidate;
        break;
      }
    }
    if (preset != null) {
      return AiFeatureSetting(
        activePresetId: presetId,
        cli: preset.cli,
        providerId: preset.provider,
        model: preset.model,
        effort: preset.effort,
      );
    }
  }

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
    activePresetId: stored?.activePresetId,
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

/// Whether the user has explicitly saved AI feature settings (preset or custom).
///
/// [stored] must be non-null — global provider defaults alone do not count.
bool aiFeatureIsConfigured({
  required AiFeatureSetting? stored,
  required CliToolRegistry registry,
  required AppProviderState appProviders,
  List<CliPreset> globalPresets = const [],
}) {
  if (stored == null) return false;

  final presetId = stored.activePresetId?.trim();
  if (presetId != null && presetId.isNotEmpty) {
    for (final preset in globalPresets) {
      if (preset.id == presetId) return true;
    }
    return false;
  }

  final providerId = stored.providerId.trim();
  if (providerId.isEmpty) return false;

  final providers = aiFeatureProvidersForCli(
    stored.cli,
    appProviders,
    registry,
  );
  final provider = providers.where((p) => p.id == providerId).firstOrNull;
  if (provider == null) return false;

  final modelCapability = registry.capability<ProviderModelCapability>(
    stored.cli,
  );
  if (modelCapability != null &&
      modelCapability.pickerMode(provider) == ProviderModelPickerMode.hidden) {
    return true;
  }
  return stored.model.trim().isNotEmpty;
}

/// Config line under the feature intro (preset name or CLI · provider · model).
String aiFeatureConfigLine({
  required AppLocalizations l10n,
  required CliToolRegistry registry,
  required bool configured,
  required AiFeatureSetting? stored,
  required AiFeatureSetting resolved,
  AppProviderConfig? provider,
  required bool hidesModelPicker,
  List<CliPreset> globalPresets = const [],
}) {
  if (!configured) return l10n.projectCliNotConfiguredHint;

  final presetId = stored?.activePresetId?.trim();
  if (presetId != null && presetId.isNotEmpty) {
    for (final preset in globalPresets) {
      if (preset.id == presetId) {
        final def = registry.tryGet(preset.cli);
        final cliLabel = def == null
            ? preset.cli.value
            : cliDisplayName(def, l10n);
        final providerName = provider?.name.trim() ?? preset.provider.trim();
        final modelLabel = preset.model.trim();
        final effortLabel = preset.effort.trim();
        final head = '${preset.name} · $cliLabel';
        if (providerName.isEmpty) return head;
        if (modelLabel.isEmpty && hidesModelPicker) {
          if (effortLabel.isEmpty) return '$head · $providerName';
          return '$head · $providerName · $effortLabel';
        }
        if (modelLabel.isEmpty) {
          if (effortLabel.isEmpty) return '$head · $providerName';
          return '$head · $providerName · $effortLabel';
        }
        if (effortLabel.isEmpty) {
          return '$head · $providerName · $modelLabel';
        }
        return '$head · $providerName · $modelLabel · $effortLabel';
      }
    }
  }

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
