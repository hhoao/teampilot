import 'package:flutter/material.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../models/launch_security_policy.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared permission menu chip for Landing and History continue chrome.
///
/// The chip stores normalized policies and exposes named intermediate presets.
class ComposePermissionChip extends StatelessWidget {
  const ComposePermissionChip({
    required this.palette,
    required this.launchSecurityPolicy,
    required this.defaultLabel,
    required this.fullAccessLabel,
    required this.onSelected,
    this.askReadOnlyLabel,
    this.autoApproveWorkspaceWriteLabel,
    this.customLabel,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final LaunchSecurityPolicy launchSecurityPolicy;
  final String defaultLabel;
  final String fullAccessLabel;
  final String? askReadOnlyLabel;
  final String? autoApproveWorkspaceWriteLabel;
  final String? customLabel;
  final ValueChanged<LaunchSecurityPolicy> onSelected;

  String get _chipLabel {
    if (launchSecurityPolicy == LaunchSecurityPolicy.fullAccess) {
      return fullAccessLabel;
    }
    if (launchSecurityPolicy == LaunchSecurityPolicy.askReadOnlyTrusted) {
      return askReadOnlyLabel ?? customLabel ?? defaultLabel;
    }
    if (launchSecurityPolicy ==
        LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted) {
      return autoApproveWorkspaceWriteLabel ?? customLabel ?? defaultLabel;
    }
    if (launchSecurityPolicy == const LaunchSecurityPolicy()) {
      return defaultLabel;
    }
    return customLabel ?? defaultLabel;
  }

  List<TpActionMenuSpec> _specs() {
    final specs = <TpActionMenuSpec>[
      TpActionMenuSpec.item(
        value: const LaunchSecurityPolicy(),
        icon: Icons.verified_outlined,
        label: defaultLabel,
        selected: launchSecurityPolicy == const LaunchSecurityPolicy(),
      ),
      if (askReadOnlyLabel != null)
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.askReadOnlyTrusted,
          icon: Icons.visibility_outlined,
          label: askReadOnlyLabel!,
          selected:
              launchSecurityPolicy == LaunchSecurityPolicy.askReadOnlyTrusted,
        ),
      if (autoApproveWorkspaceWriteLabel != null)
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
          icon: Icons.edit_note_outlined,
          label: autoApproveWorkspaceWriteLabel!,
          selected:
              launchSecurityPolicy ==
              LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
        ),
      TpActionMenuSpec.item(
        value: LaunchSecurityPolicy.fullAccess,
        icon: Icons.lock_open_outlined,
        label: fullAccessLabel,
        selected: launchSecurityPolicy == LaunchSecurityPolicy.fullAccess,
      ),
    ];
    return specs;
  }

  @override
  Widget build(BuildContext context) {
    return ComposeMenuChip(
      palette: palette,
      icon: Icons.verified_outlined,
      label: _chipLabel,
      specs: _specs(),
      onSelected: (value) {
        if (value is LaunchSecurityPolicy) onSelected(value);
      },
    );
  }
}
