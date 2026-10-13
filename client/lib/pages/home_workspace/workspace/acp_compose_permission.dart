import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/session_member_binding.dart';
import '../../../models/team_config.dart';
import '../../../widgets/compose/compose_chrome.dart';
import 'claude_acp_launch_switch.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

/// Gemini personal desktop always launches ACP; otherwise [resolveLaunchAcp].
bool willLaunchPersonalAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (isPersonal && cli == CliTool.gemini && !_isAndroid(isAndroidOverride)) {
    return true;
  }
  return resolveLaunchAcp(
    isPersonal: isPersonal,
    cli: cli,
    requested: requested,
    isAndroidOverride: isAndroidOverride,
  );
}

/// Whether Landing should show the ACP Ask / Full access permission chip.
bool showLandingAcpPermissionChip({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  List<SessionMemberBinding> stampedMembers = const [],
  bool? isAndroidOverride,
}) {
  if (_isAndroid(isAndroidOverride)) return false;
  if (isPersonal) {
    return willLaunchPersonalAcp(
      isPersonal: true,
      cli: cli,
      requested: requested,
      isAndroidOverride: isAndroidOverride,
    );
  }
  return stampedMembers.any((member) => member.acp);
}

/// Compose chrome for ACP Ask vs Full access, or null when the pair is incomplete.
ComposePermissionControl? acpComposePermissionControl({
  required LaunchSecurityPolicy current,
  required Set<LaunchSecurityPolicy> supported,
  required AppLocalizations l10n,
  required ValueChanged<LaunchSecurityPolicy> onSelected,
}) {
  if (supported.length <= 1 ||
      !supported.contains(LaunchSecurityPolicy.ask) ||
      !supported.contains(LaunchSecurityPolicy.fullAccess)) {
    return null;
  }
  return ComposePermissionControl(
    launchSecurityPolicy: current,
    supportedPolicies: supported,
    defaultLabel: l10n.acpPermissionAskLabel,
    fullAccessLabel: l10n.acpPermissionFullAccessLabel,
    askLabel: l10n.acpPermissionAskLabel,
    onSelected: onSelected,
  );
}
