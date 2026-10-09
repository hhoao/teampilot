import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../utils/ui/app_keys.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

/// Whether the compose ACP switch applies: personal Claude on a non-Android
/// platform (ACP spawns a local process; Android has no local exec).
bool claudeAcpLaunchSwitchVisible({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) => isPersonal && cli == CliTool.claude && !_isAndroid(isAndroidOverride);

/// Final ACP flag for a launch: [requested] only counts for personal Claude
/// and is always false on Android. Gemini ACP is inferred by session create.
bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    claudeAcpLaunchSwitchVisible(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );

/// Current settings default for "personal Claude uses ACP"; false when the
/// preferences cubit is not in scope.
bool readClaudePersonalAcpDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .claudePersonalAcpDefault;
  } on ProviderNotFoundException {
    return false;
  }
}

/// Landing compose switch: start this one personal Claude session as ACP chat.
///
/// The value follows the settings default until the user flips it ([override]
/// is non-null); flipping never writes the preference.
class ClaudeAcpLaunchSwitch extends StatelessWidget {
  const ClaudeAcpLaunchSwitch({
    required this.cli,
    required this.isPersonal,
    required this.localOverride,
    required this.onChanged,
    @visibleForTesting this.isAndroidOverride,
    super.key,
  });

  final CliTool? cli;
  final bool isPersonal;

  /// Local choice for this compose; null follows the settings default.
  final bool? localOverride;
  final ValueChanged<bool> onChanged;
  final bool? isAndroidOverride;

  @override
  Widget build(BuildContext context) {
    if (!claudeAcpLaunchSwitchVisible(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    )) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final preferenceDefault = _watchPreferenceDefault(context);
    return SwitchListTile(
      key: AppKeys.claudeAcpLaunchSwitch,
      dense: true,
      title: Text(l10n.claudePersonalAcpDefaultLabel),
      subtitle: Text(l10n.claudePersonalAcpDefaultDescription),
      value: localOverride ?? preferenceDefault,
      onChanged: onChanged,
    );
  }

  bool _watchPreferenceDefault(BuildContext context) {
    try {
      return context.select<SessionPreferencesCubit, bool>(
        (c) => c.state.preferences.claudePersonalAcpDefault,
      );
    } on ProviderNotFoundException {
      return false;
    }
  }
}
