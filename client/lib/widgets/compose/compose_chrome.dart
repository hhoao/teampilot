import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/cli_preset.dart';

sealed class ComposeChrome {
  const ComposeChrome();
}

/// Toolbar chrome for landing / unbound compose (conversation mode, auto, expert chips).
final class UnboundComposeChrome extends ComposeChrome {
  const UnboundComposeChrome({
    required this.conversationModeLabel,
    required this.autoChipLabel,
    required this.dangerouslySkipPermissions,
    required this.defaultPermissionsLabel,
    required this.fullAccessPermissionsLabel,
    required this.conversationModeSpecs,
    required this.autoChipSpecs,
    required this.onConversationModeSelected,
    required this.onAutoChipSelected,
    required this.onPermissionSelected,
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
  final bool dangerouslySkipPermissions;
  final String defaultPermissionsLabel;
  final String fullAccessPermissionsLabel;
  final List<TpActionMenuSpec> conversationModeSpecs;
  final List<TpActionMenuSpec> autoChipSpecs;
  final ValueChanged<Object?> onConversationModeSelected;
  final ValueChanged<Object?> onAutoChipSelected;
  final ValueChanged<bool> onPermissionSelected;
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
    this.sameCliPresets = const [],
    this.selectedPresetId,
    this.modelPresetLabel,
    this.emptyPresetHintLabel,
    this.onPresetSelected,
    this.customLabel,
    this.customSelected = false,
    this.onCustom,
    this.dangerouslySkipPermissions = false,
    this.defaultPermissionsLabel,
    this.fullAccessPermissionsLabel,
    this.onPermissionSelected,
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

  final List<CliPreset> sameCliPresets;
  final String? selectedPresetId;
  final String? modelPresetLabel;
  final String? emptyPresetHintLabel;
  final ValueChanged<String>? onPresetSelected;
  final String? customLabel;
  final bool customSelected;
  final VoidCallback? onCustom;

  final bool dangerouslySkipPermissions;
  final String? defaultPermissionsLabel;
  final String? fullAccessPermissionsLabel;
  final ValueChanged<bool>? onPermissionSelected;

  final String? teamSettingsTooltip;
  final VoidCallback? onTeamSettings;
  final bool showTeamSettingsAttention;

  /// When true, the send button is replaced with a stop-generating control.
  final bool showStop;
  final VoidCallback? onStop;
}
