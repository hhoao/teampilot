import 'package:flutter/material.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../cli/cli_brand_icon.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Sentinel values for optional model chip menu rows.
enum ComposeModelPresetChipAction {
  custom,
  manage,
}

/// Summary label for Simple launch model chips (preset or custom four-tuple).
String simpleLaunchChipLabel({
  required String? presetName,
  required CliTool? cli,
  required String? provider,
  required String? model,
  required String emptyLabel,
  required String Function(CliTool cli) cliLabel,
}) {
  final trimmedPreset = presetName?.trim() ?? '';
  if (trimmedPreset.isNotEmpty) return trimmedPreset;
  if (cli == null) return emptyLabel;

  final cliName = cliLabel(cli);
  final trimmedModel = model?.trim() ?? '';
  if (trimmedModel.isNotEmpty) return '$cliName · $trimmedModel';

  final trimmedProvider = provider?.trim() ?? '';
  if (trimmedProvider.isNotEmpty) return '$cliName · $trimmedProvider';

  return cliName;
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
