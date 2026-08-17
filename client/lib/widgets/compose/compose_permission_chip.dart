import 'package:flutter/material.dart';

import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../models/launch_security_policy.dart';
import 'compose_menu_chip.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared permission menu chip for Landing and History continue chrome.
///
/// The chip keeps the existing two-choice UI while storing a normalized policy.
class ComposePermissionChip extends StatelessWidget {
  const ComposePermissionChip({
    required this.palette,
    required this.launchSecurityPolicy,
    required this.defaultLabel,
    required this.fullAccessLabel,
    required this.onSelected,
    super.key,
  });

  final WorkspaceChatLandingPalette palette;
  final LaunchSecurityPolicy launchSecurityPolicy;
  final String defaultLabel;
  final String fullAccessLabel;
  final ValueChanged<LaunchSecurityPolicy> onSelected;

  String get _chipLabel => launchSecurityPolicy.requiresDangerousExecution
      ? fullAccessLabel
      : defaultLabel;

  List<TpActionMenuSpec> _specs() {
    return [
      TpActionMenuSpec.item(
        value: const LaunchSecurityPolicy(),
        icon: Icons.verified_outlined,
        label: defaultLabel,
        selected: !launchSecurityPolicy.requiresDangerousExecution,
      ),
      TpActionMenuSpec.item(
        value: LaunchSecurityPolicy.fullAccess,
        icon: Icons.lock_open_outlined,
        label: fullAccessLabel,
        selected: launchSecurityPolicy.requiresDangerousExecution,
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
        if (value is LaunchSecurityPolicy) onSelected(value);
      },
    );
  }
}
