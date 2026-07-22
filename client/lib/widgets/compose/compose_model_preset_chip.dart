import 'package:flutter/material.dart';

import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../cli/cli_brand_icon.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Sentinel for the optional "manage presets" menu row.
abstract final class ComposeModelPresetChipAction {
  static const manage = Object();
}

/// Builds preset menu specs for same-CLI preset pickers.
///
/// Caller must filter [sameCliPresets] with [presetsForCli] when needed.
List<TpActionMenuSpec> buildComposeModelPresetMenuSpecs({
  required List<CliPreset> sameCliPresets,
  required String? selectedPresetId,
  required String emptyHintLabel,
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
  if (managePresetsLabel != null) {
    specs.add(const TpActionMenuSpec.divider());
    specs.add(
      TpActionMenuSpec.item(
        value: ComposeModelPresetChipAction.manage,
        icon: Icons.add,
        label: managePresetsLabel,
      ),
    );
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
  final String? managePresetsLabel;
  final VoidCallback? onManagePresets;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ComposeMenuChip(
      palette: palette,
      icon: icon,
      label: label,
      specs: buildComposeModelPresetMenuSpecs(
        sameCliPresets: sameCliPresets,
        selectedPresetId: selectedPresetId,
        emptyHintLabel: emptyHintLabel,
        managePresetsLabel: managePresetsLabel,
      ),
      onSelected: (value) {
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
