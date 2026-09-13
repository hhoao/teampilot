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
    required this.supportedPolicies,
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

  /// Immutable policies exposed by the CLI capability for this chip.
  final Set<LaunchSecurityPolicy> supportedPolicies;
  final LaunchSecurityPolicy launchSecurityPolicy;
  final String defaultLabel;
  final String fullAccessLabel;
  final String? askReadOnlyLabel;
  final String? autoApproveWorkspaceWriteLabel;
  final String? customLabel;
  final ValueChanged<LaunchSecurityPolicy> onSelected;

  LaunchSecurityPolicy? get _effectiveLaunchSecurityPolicy {
    if (supportedPolicies.isEmpty) return null;
    return supportedPolicies.contains(launchSecurityPolicy)
        ? launchSecurityPolicy
        : supportedPolicies.first;
  }

  String get _chipLabel {
    final policy = _effectiveLaunchSecurityPolicy;
    if (policy == LaunchSecurityPolicy.fullAccess) {
      return fullAccessLabel;
    }
    if (policy == LaunchSecurityPolicy.askReadOnlyTrusted) {
      return askReadOnlyLabel ?? customLabel ?? defaultLabel;
    }
    if (policy == LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted) {
      return autoApproveWorkspaceWriteLabel ?? customLabel ?? defaultLabel;
    }
    if (policy == LaunchSecurityPolicy.cliDefault) {
      return defaultLabel;
    }
    return customLabel ?? defaultLabel;
  }

  List<TpActionMenuSpec> _specs() {
    final selectedPolicy = _effectiveLaunchSecurityPolicy;
    final specs = <TpActionMenuSpec>[
      if (supportedPolicies.contains(LaunchSecurityPolicy.cliDefault))
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.cliDefault,
          icon: Icons.verified_outlined,
          label: defaultLabel,
          selected: selectedPolicy == LaunchSecurityPolicy.cliDefault,
        ),
      if (supportedPolicies.contains(LaunchSecurityPolicy.askReadOnlyTrusted) &&
          askReadOnlyLabel != null)
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.askReadOnlyTrusted,
          icon: Icons.visibility_outlined,
          label: askReadOnlyLabel!,
          selected: selectedPolicy == LaunchSecurityPolicy.askReadOnlyTrusted,
        ),
      if (supportedPolicies.contains(
            LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
          ) &&
          autoApproveWorkspaceWriteLabel != null)
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
          icon: Icons.edit_note_outlined,
          label: autoApproveWorkspaceWriteLabel!,
          selected:
              selectedPolicy ==
              LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
        ),
      if (supportedPolicies.contains(LaunchSecurityPolicy.fullAccess))
        TpActionMenuSpec.item(
          value: LaunchSecurityPolicy.fullAccess,
          icon: Icons.lock_open_outlined,
          label: fullAccessLabel,
          selected: selectedPolicy == LaunchSecurityPolicy.fullAccess,
        ),
    ];
    return specs;
  }

  @override
  Widget build(BuildContext context) {
    final specs = _specs();
    if (specs.isEmpty) return const SizedBox.shrink();
    return ComposeMenuChip(
      palette: palette,
      icon: Icons.verified_outlined,
      label: _chipLabel,
      specs: specs,
      onSelected: (value) {
        if (value is LaunchSecurityPolicy) onSelected(value);
      },
    );
  }
}
