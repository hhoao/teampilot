import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/launch_security_policy.dart';

sealed class ComposeChrome {
  const ComposeChrome();
}

final class ComposePermissionControl {
  const ComposePermissionControl({
    required this.launchSecurityPolicy,
    required this.defaultLabel,
    required this.fullAccessLabel,
    required this.onSelected,
    this.askReadOnlyLabel,
    this.autoApproveWorkspaceWriteLabel,
    this.customLabel,
  });

  final LaunchSecurityPolicy launchSecurityPolicy;
  final String defaultLabel;
  final String fullAccessLabel;
  final String? askReadOnlyLabel;
  final String? autoApproveWorkspaceWriteLabel;
  final String? customLabel;
  final ValueChanged<LaunchSecurityPolicy> onSelected;
}

/// Toolbar chrome for landing / unbound compose (conversation mode, auto, expert chips).
final class UnboundComposeChrome extends ComposeChrome {
  const UnboundComposeChrome({
    required this.conversationModeLabel,
    required this.autoChipLabel,
    this.permissionControl,
    required this.conversationModeSpecs,
    required this.autoChipSpecs,
    required this.onConversationModeSelected,
    required this.onAutoChipSelected,
    this.autoChipLeading,
    this.expertChipLabel,
    this.expertChipSpecs = const [],
    this.onExpertChipSelected,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
  });

  final String conversationModeLabel;
  final String autoChipLabel;
  final ComposePermissionControl? permissionControl;
  final List<TpActionMenuSpec> conversationModeSpecs;
  final List<TpActionMenuSpec> autoChipSpecs;
  final ValueChanged<Object?> onConversationModeSelected;
  final ValueChanged<Object?> onAutoChipSelected;
  final Widget? autoChipLeading;
  final String? expertChipLabel;
  final List<TpActionMenuSpec> expertChipSpecs;
  final ValueChanged<Object?>? onExpertChipSelected;
  final String? teamSettingsTooltip;
  final VoidCallback? onTeamSettings;
  final bool showTeamSettingsAttention;
}

/// Toolbar chrome for session continue compose (identity, preset, permissions).
final class BoundComposeChrome extends ComposeChrome {
  const BoundComposeChrome({
    this.composeEnabled = true,
    this.launchError,
    this.onRemapDeadTarget,
    this.onRetry,
    this.sessionConnectInProgress = false,
    this.floating = false,
    this.identityLabel,
    this.identityIcon,
    this.modelPresetLabel,
    this.modelChipLeading,
    this.modelCascadeSpecs,
    this.onModelCascadeSelected,
    this.permissionControl,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
    this.showStop = false,
    this.onStop,
  });

  /// When false, field and toolbar actions are locked (e.g. permission wait).
  final bool composeEnabled;
  final String? launchError;
  final VoidCallback? onRemapDeadTarget;
  final VoidCallback? onRetry;
  final bool sessionConnectInProgress;
  final bool floating;

  /// Read-only expert / team identity (no menu).
  final String? identityLabel;
  final IconData? identityIcon;

  final String? modelPresetLabel;
  final Widget? modelChipLeading;
  final List<TpActionMenuSpec>? modelCascadeSpecs;
  final ValueChanged<Object?>? onModelCascadeSelected;

  final ComposePermissionControl? permissionControl;

  final String? teamSettingsTooltip;
  final VoidCallback? onTeamSettings;
  final bool showTeamSettingsAttention;

  /// When true, the send button is replaced with a stop-generating control.
  final bool showStop;
  final VoidCallback? onStop;
}
