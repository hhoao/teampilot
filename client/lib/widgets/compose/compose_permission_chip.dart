import 'package:flutter/material.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared permission menu chip for Landing and History continue chrome.
///
/// [dangerouslySkipPermissions] is the effective bool (full access when true).
/// [onSelected] always receives a concrete bool — never null.
class ComposePermissionChip extends StatelessWidget {
  const ComposePermissionChip({
    required this.palette,
    required this.dangerouslySkipPermissions,
    required this.defaultLabel,
    required this.fullAccessLabel,
    required this.onSelected,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final bool dangerouslySkipPermissions;
  final String defaultLabel;
  final String fullAccessLabel;
  final ValueChanged<bool> onSelected;

  String get _chipLabel =>
      dangerouslySkipPermissions ? fullAccessLabel : defaultLabel;

  List<TpActionMenuSpec> _specs() {
    return [
      TpActionMenuSpec.item(
        value: false,
        icon: Icons.verified_outlined,
        label: defaultLabel,
        selected: !dangerouslySkipPermissions,
      ),
      TpActionMenuSpec.item(
        value: true,
        icon: Icons.lock_open_outlined,
        label: fullAccessLabel,
        selected: dangerouslySkipPermissions,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ComposeMenuChip(
      palette: palette,
      icon: Icons.verified_outlined,
      label: _chipLabel,
      specs: _specs(),
      onSelected: (value) {
        if (value is bool) onSelected(value);
      },
    );
  }
}
