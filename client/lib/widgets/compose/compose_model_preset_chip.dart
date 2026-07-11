import 'package:flutter/material.dart';

import '../../models/cli_preset.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../menu/sidebar_action_menu.dart';
import 'compose_menu_chip.dart';

/// Sentinel for the optional "manage presets" menu row.
abstract final class ComposeModelPresetChipAction {
  static const manage = Object();
}

/// Builds preset menu specs for same-CLI preset pickers.
///
/// Caller must filter [sameCliPresets] with [presetsForCli] when needed.
List<SidebarActionMenuSpec> buildComposeModelPresetMenuSpecs({
  required List<CliPreset> sameCliPresets,
  required String? selectedPresetId,
  required String emptyHintLabel,
  String? managePresetsLabel,
}) {
  final specs = <SidebarActionMenuSpec>[
    if (sameCliPresets.isEmpty)
      SidebarActionMenuSpec.item(
        value: null,
        icon: Icons.tune,
        label: emptyHintLabel,
        enabled: false,
      )
    else
      for (final preset in sameCliPresets)
        SidebarActionMenuSpec.item(
          value: preset.id,
          icon: Icons.tune,
          label: preset.name,
          selected: preset.id == selectedPresetId,
        ),
  ];
  if (managePresetsLabel != null) {
    specs.add(const SidebarActionMenuSpec.divider());
    specs.add(
      SidebarActionMenuSpec.item(
        value: ComposeModelPresetChipAction.manage,
        icon: Icons.add,
        label: managePresetsLabel,
      ),
    );
  }
  return specs;
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
    this.icon = Icons.tune,
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
