import 'package:flutter/material.dart';

import '../../models/app_provider_config.dart';
import '../../models/cli_preset.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../services/cli/registry/capabilities/provider_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../cli/cli_brand_icon.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Sentinel values for optional model chip menu rows.
enum ComposeModelPresetChipAction {
  custom,
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
  final Map<String, List<String>> effortByModel; // value empty ⇒ model is a leaf
  const ComposeCascadeProvider({
    required this.id,
    required this.name,
    required this.supportsCustomModelEntry,
    required this.models,
    required this.effortByModel,
  });
}

class ComposeCascadeCliGroup {
  final CliTool cli;
  final List<ComposeCascadeProvider> providers;
  const ComposeCascadeCliGroup({required this.cli, required this.providers});
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
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

List<TpActionMenuSpec> buildComposeModelCascadeMenuSpecs({
  required List<CliPreset> presets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  required String defaultEffortLabel,
  required String customModelIdLabel,
  required String noModelsLabel,
  required String savePresetLabel,
  required String managePresetsLabel,
  required List<ComposeCascadeCliGroup> cliGroups,
  required bool groupByCli,
  void Function(CliTool cli, String providerId)? onModelsOpened,
}) {
  List<TpActionMenuSpec> providerChildren(ComposeCascadeCliGroup group,
      ComposeCascadeProvider p) {
    final rows = <TpActionMenuSpec>[
      if (p.models.isEmpty)
        TpActionMenuSpec.item(
          value: null, icon: Icons.cloud_off_outlined,
          label: noModelsLabel, enabled: false)
      else
        for (final model in p.models)
          if ((p.effortByModel[model]?.isNotEmpty ?? false))
            TpActionMenuSpec.submenu(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              icon: Icons.memory_outlined,
              label: model,
              onOpen: () => onModelsOpened?.call(group.cli, p.id),
              children: [
                TpActionMenuSpec.item(
                  value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
                  icon: Icons.speed_outlined, label: defaultEffortLabel,
                  selected: false),
                for (final e in p.effortByModel[model]!)
                  TpActionMenuSpec.item(
                    value: CascadeEffortPick(cli: group.cli, providerId: p.id,
                      modelId: model, effort: e),
                    icon: Icons.speed_outlined, label: e),
              ],
            )
          else
            TpActionMenuSpec.item(
              value: CascadeModelPick(cli: group.cli, providerId: p.id, modelId: model),
              icon: Icons.memory_outlined, label: model),
      if (p.supportsCustomModelEntry)
        TpActionMenuSpec.item(
          value: CascadeCustomModelRequest(cli: group.cli, providerId: p.id),
          icon: Icons.edit_outlined, label: customModelIdLabel),
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

  final specs = <TpActionMenuSpec>[
    if (presets.isEmpty)
      TpActionMenuSpec.item(value: null, icon: Icons.terminal_outlined,
        label: emptyHintLabel, enabled: false)
    else
      for (final preset in presets)
        TpActionMenuSpec.item(value: preset.id,
          iconWidget: _PresetCliMenuIcon(cli: preset.cli),
          label: preset.name, selected: preset.id == selectedPresetId),
    const TpActionMenuSpec.divider(),
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
    const TpActionMenuSpec.divider(),
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

/// Builds preset menu specs for same-CLI preset pickers.
///
/// Caller must filter [sameCliPresets] with [presetsForCli] when needed.
List<TpActionMenuSpec> buildComposeModelPresetMenuSpecs({
  required List<CliPreset> sameCliPresets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  String? customLabel,
  bool customSelected = false,
  String? managePresetsLabel,
}) {
  final specs = <TpActionMenuSpec>[
    if (sameCliPresets.isEmpty)
      TpActionMenuSpec.item(
        value: null,
        icon: Icons.terminal_outlined,
        label: emptyHintLabel,
        enabled: false,
      )
    else
      for (final preset in sameCliPresets)
        TpActionMenuSpec.item(
          value: preset.id,
          iconWidget: _PresetCliMenuIcon(cli: preset.cli),
          label: preset.name,
          selected: preset.id == selectedPresetId,
        ),
  ];
  if (customLabel != null || managePresetsLabel != null) {
    specs.add(const TpActionMenuSpec.divider());
    if (customLabel != null) {
      specs.add(
        TpActionMenuSpec.item(
          value: ComposeModelPresetChipAction.custom,
          icon: Icons.tune_outlined,
          label: customLabel,
          selected: customSelected,
        ),
      );
    }
    if (managePresetsLabel != null) {
      specs.add(
        TpActionMenuSpec.item(
          value: ComposeModelPresetChipAction.manage,
          icon: Icons.add,
          label: managePresetsLabel,
        ),
      );
    }
  }
  return specs;
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

/// Shared same-CLI preset menu chip for Landing and History continue chrome.
class ComposeModelPresetChip extends StatelessWidget {
  const ComposeModelPresetChip({
    required this.palette,
    required this.sameCliPresets,
    required this.selectedPresetId,
    required this.label,
    required this.emptyHintLabel,
    required this.onPresetSelected,
    this.customLabel,
    this.customSelected = false,
    this.onCustom,
    this.managePresetsLabel,
    this.onManagePresets,
    this.icon = Icons.terminal_outlined,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final List<CliPreset> sameCliPresets;
  final String? selectedPresetId;
  final String label;
  final String emptyHintLabel;
  final ValueChanged<String> onPresetSelected;
  final String? customLabel;
  final bool customSelected;
  final VoidCallback? onCustom;
  final String? managePresetsLabel;
  final VoidCallback? onManagePresets;
  final IconData icon;

  CliTool? get _triggerCli {
    final selected = selectedPresetId == null
        ? null
        : sameCliPresets.where((p) => p.id == selectedPresetId).firstOrNull;
    return selected?.cli ?? sameCliPresets.firstOrNull?.cli;
  }

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final cli = _triggerCli;
    return ComposeMenuChip(
      palette: palette,
      icon: icon,
      leading: cli == null
          ? null
          : CliBrandIcon(
              cli: cli,
              size: icons.sm,
              borderRadius: 4,
              showBorder: false,
            ),
      label: label,
      specs: buildComposeModelPresetMenuSpecs(
        sameCliPresets: sameCliPresets,
        selectedPresetId: selectedPresetId,
        emptyHintLabel: emptyHintLabel,
        customLabel: customLabel,
        customSelected: customSelected,
        managePresetsLabel: managePresetsLabel,
      ),
      onSelected: (value) {
        if (value == ComposeModelPresetChipAction.custom) {
          onCustom?.call();
          return;
        }
        if (value == ComposeModelPresetChipAction.manage) {
          onManagePresets?.call();
          return;
        }
        if (value is String && value.isNotEmpty) {
          onPresetSelected(value);
        }
      },
    );
  }
}
