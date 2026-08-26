import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../services/cli/registry/capabilities/provider_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../utils/logging/logger_utils.dart';
import '../cli/cli_brand_icon.dart';
import 'package:shared_ui/shared_ui.dart';

/// Fixed max-height applied to the scrollable presets group in the cascade
/// menu so a long preset list doesn't push provider/actions out of view.
const double kComposeCascadePresetsMaxHeight = 320;

/// Sentinel values for optional model chip menu rows.
enum ComposeModelPresetChipAction {
  manage,
  savePreset,
}

sealed class CascadeSelection {
  final CliTool cli;
  final String providerId;
  const CascadeSelection({required this.cli, required this.providerId});
}

final class CascadeModelPick extends CascadeSelection {
  // Direct model-row pick: effort stays empty (identical to today's modal submit).
  final String modelId;
  const CascadeModelPick({required super.cli, required super.providerId, required this.modelId});
}

final class CascadeEffortPick extends CascadeSelection {
  final String modelId;
  final String effort;
  const CascadeEffortPick({required super.cli, required super.providerId, required this.modelId, required this.effort});
}

final class CascadeCustomModelRequest extends CascadeSelection {
  const CascadeCustomModelRequest({required super.cli, required super.providerId});
}

class ComposeCascadeProvider {
  final String id;
  final String name;
  final bool supportsCustomModelEntry;
  final List<String> models;
  final AppProviderConfig config;
  final Map<String, List<String>> effortByModel; // value empty ⇒ model is a leaf
  const ComposeCascadeProvider({
    required this.id,
    required this.name,
    required this.supportsCustomModelEntry,
    required this.models,
    required this.config,
    required this.effortByModel,
  });
}

class ComposeCascadeCliGroup {
  final CliTool cli;
  final List<ComposeCascadeProvider> providers;
  const ComposeCascadeCliGroup({required this.cli, required this.providers});
}

/// Aggregates the `catalogUpdates` listenables of the involved CLIs' provider
/// capabilities so open cascade menus rebuild when a live catalog refresh
/// lands.
final class CascadeCatalogListenable extends ChangeNotifier {
  CascadeCatalogListenable({required CliToolRegistry registry})
    : _registry = registry;

  final CliToolRegistry _registry;
  final Set<ProviderCapability> _capabilities = <ProviderCapability>{};

  void attach(Iterable<CliTool> clis) {
    detach();
    for (final cli in clis) {
      final capability = _registry.capability<ProviderCapability>(cli);
      if (capability == null || !_capabilities.add(capability)) continue;
      capability.catalogUpdates.addListener(notifyListeners);
    }
  }

  void detach() {
    for (final capability in _capabilities) {
      capability.catalogUpdates.removeListener(notifyListeners);
    }
    _capabilities.clear();
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}

List<ComposeCascadeCliGroup> resolveComposeCascadeCliGroups({
  required CliToolRegistry registry,
  required Map<CliTool, List<AppProviderConfig>> providersByCli,
  required List<CliTool> cliItems,
}) {
  final groups = <ComposeCascadeCliGroup>[];
  for (final cli in cliItems) {
    final capability = registry.capability<ProviderCapability>(cli);
    if (capability == null) continue;
    final providers = [...providersByCli[cli] ?? const <AppProviderConfig>[]]
      ..sort((a, b) {
        final byCategory = a.category.index.compareTo(b.category.index);
        if (byCategory != 0) return byCategory;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    if (providers.isEmpty) continue;
    final cascadeProviders = <ComposeCascadeProvider>[];
    for (final p in providers) {
      final mode = capability.pickerMode(p);
      final models = mode == ProviderModelPickerMode.hidden
          ? const <String>[]
          : capability.modelCandidates(provider: p, providerId: p.id, currentModel: '');
      cascadeProviders.add(ComposeCascadeProvider(
        id: p.id,
        name: p.name,
        supportsCustomModelEntry:
            mode == ProviderModelPickerMode.catalogWithCustomEntry,
        models: models,
        config: p,
        effortByModel: {
          for (final m in models)
            m: capability.isApplicable(model: m)
                ? capability.effortCandidates(model: m, provider: p)
                : const <String>[],
        },
      ));
    }
    groups.add(ComposeCascadeCliGroup(cli: cli, providers: cascadeProviders));
  }
  return groups;
}

Future<void> refreshComposeCascadeCatalog(
  BuildContext context, {
  required CliTool cli,
  required String providerId,
  required AppProviderConfig? provider,
}) async {
  final registry = CliToolRegistryScope.maybeOf(context);
  final capability = registry?.capability<ProviderCapability>(cli);
  if (capability is! RefreshableProviderModelCapability) return;
  SessionPreferencesCubit? prefs;
  try {
    prefs = context.read<SessionPreferencesCubit>();
  } on ProviderNotFoundException {
    prefs = null;
  }
  try {
    await capability.refreshModelCatalog(
      providerId: providerId,
      provider: provider,
      executable: prefs?.resolveExecutable(cli),
    );
  } on Object catch (error) {
    AppLogger.instance.d(
      'Compose cascade model catalog refresh failed for $providerId: $error',
    );
  }
}

/// Decodes a cascade menu value into a concrete launch four-tuple request.
/// Returns null when [value] needs dialog interaction first (custom model id)
/// or is a pure action (manage/save-preset handled by callers).
SimpleLaunchFourTuple? decodeComposeCascadeValue(Object? value) {
  if (value is CascadeEffortPick) {
    return SimpleLaunchFourTuple(
      cli: value.cli,
      providerId: value.providerId,
      modelId: value.modelId,
      effort: value.effort,
    );
  }
  if (value is CascadeModelPick) {
    return SimpleLaunchFourTuple(
      cli: value.cli,
      providerId: value.providerId,
      modelId: value.modelId,
      effort: '',
    );
  }
  return null;
}

class SimpleLaunchFourTuple {
  final CliTool cli;
  final String providerId;
  final String modelId;
  final String effort;
  const SimpleLaunchFourTuple({
    required this.cli,
    required this.providerId,
    required this.modelId,
    required this.effort,
  });
}

List<TpActionMenuSpec> buildComposeModelCascadeMenuSpecs({
  required List<CliPreset> presets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  required String emptyProvidersLabel,
  required String defaultEffortLabel,
  required String customModelIdLabel,
  required String noModelsLabel,
  required String savePresetLabel,
  required String managePresetsLabel,
  required List<ComposeCascadeCliGroup> cliGroups,
  required bool groupByCli,
  void Function(CliTool cli, String providerId, AppProviderConfig config)?
  onModelsOpened,
}) {
  List<TpActionMenuSpec> providerChildren(ComposeCascadeCliGroup group,
      ComposeCascadeProvider p) {
    final rows = <TpActionMenuSpec>[
      if (p.models.isEmpty)
        TpActionMenuSpec.item(
          value: null,
          label: noModelsLabel, enabled: false)
      else
        for (final model in p.models)
          if ((p.effortByModel[model]?.isNotEmpty ?? false))
            TpActionMenuSpec.submenu(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              label: model,
              onOpen: () => onModelsOpened?.call(group.cli, p.id, p.config),
              children: [
                TpActionMenuSpec.item(
                  value: CascadeModelPick(cli: group.cli, providerId: p.id,
                    modelId: model),
                  label: defaultEffortLabel,
                  selected: false),
                for (final e in p.effortByModel[model]!)
                  TpActionMenuSpec.item(
                    value: CascadeEffortPick(cli: group.cli, providerId: p.id,
                      modelId: model, effort: e),
                    label: e),
              ],
            )
          else
            TpActionMenuSpec.item(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              label: model),
      if (p.supportsCustomModelEntry) ...[
        const TpActionMenuSpec.divider(),
        TpActionMenuSpec.item(
          value: CascadeCustomModelRequest(cli: group.cli, providerId: p.id),
          label: customModelIdLabel),
      ],
    ];
    return rows;
  }

  TpActionMenuSpec providerSpec(ComposeCascadeCliGroup group,
      ComposeCascadeProvider p) {
    return TpActionMenuSpec.submenu(
      value: p.id,
      icon: Icons.cloud_outlined,
      label: p.name,
      searchable: true,
      children: providerChildren(group, p),
    );
  }

  final hasProviderRows = cliGroups.any((g) => g.providers.isNotEmpty);

  final specs = <TpActionMenuSpec>[
    if (presets.isEmpty)
      TpActionMenuSpec.item(value: null, icon: Icons.terminal_outlined,
        label: emptyHintLabel, enabled: false)
    else
      TpActionMenuSpec.scroll(
        maxHeight: kComposeCascadePresetsMaxHeight,
        children: [
          for (final preset in presets)
            TpActionMenuSpec.item(value: preset.id,
              iconWidget: _PresetCliMenuIcon(cli: preset.cli),
              label: preset.name, selected: preset.id == selectedPresetId),
        ],
      ),
    const TpActionMenuSpec.divider(),
    if (!hasProviderRows)
      TpActionMenuSpec.item(value: null, icon: Icons.cloud_off_outlined,
        label: emptyProvidersLabel, enabled: false)
    else
      for (final group in cliGroups)
        if (!groupByCli)
          for (final p in group.providers) providerSpec(group, p)
        else if (group.providers.isNotEmpty)
          TpActionMenuSpec.submenu(
            value: group.cli,
            iconWidget: _PresetCliMenuIcon(cli: group.cli),
            label: group.cli.value,
            children: [for (final p in group.providers) providerSpec(group, p)],
          ),
    if (hasProviderRows) const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      value: ComposeModelPresetChipAction.savePreset,
      icon: Icons.bookmark_add_outlined, label: savePresetLabel),
    TpActionMenuSpec.item(
      value: ComposeModelPresetChipAction.manage,
      icon: Icons.add, label: managePresetsLabel),
  ];
  return specs;
}

/// Summary label for Simple launch model chips (preset or custom four-tuple).
///
/// Custom mode omits CLI text — the chip leading [CliBrandIcon] already
/// identifies the tool (same visual pattern as presets that show only a name).
String simpleLaunchChipLabel({
  required String? presetName,
  required CliTool? cli,
  required String? provider,
  required String? model,
  required String emptyLabel,
}) {
  final trimmedPreset = presetName?.trim() ?? '';
  if (trimmedPreset.isNotEmpty) return trimmedPreset;
  if (cli == null) return emptyLabel;

  final trimmedModel = model?.trim() ?? '';
  if (trimmedModel.isNotEmpty) return trimmedModel;

  final trimmedProvider = provider?.trim() ?? '';
  if (trimmedProvider.isNotEmpty) return trimmedProvider;

  return emptyLabel;
}

class _PresetCliMenuIcon extends StatelessWidget {
  const _PresetCliMenuIcon({required this.cli});

  final CliTool cli;

  @override
  Widget build(BuildContext context) {
    return CliBrandIcon(
      cli: cli,
      size: TpActionMenuMetrics.iconSize(context),
      borderRadius: 4,
      showBorder: false,
    );
  }
}
