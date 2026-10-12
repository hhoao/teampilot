import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../models/team_config.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

bool _personalAdapterAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) =>
    isPersonal &&
    (cli == CliTool.claude || cli == CliTool.codex) &&
    !_isAndroid(isAndroidOverride);

/// Final ACP flag for a launch: [requested] only counts for personal Claude
/// or Codex on desktop and is always false on Android. Gemini ACP is inferred
/// by session create.
bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    _personalAdapterAcpAllowed(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );

/// Current settings default for "personal Claude uses ACP"; true when the
/// preferences cubit is not in scope (matches [SessionPreferences] default).
bool readClaudePersonalAcpDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .claudePersonalAcpDefault;
  } on ProviderNotFoundException {
    return true;
  }
}

bool readCodexPersonalAcpDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .codexPersonalAcpDefault;
  } on ProviderNotFoundException {
    return false;
  }
}

bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  if (cli == CliTool.claude) return readClaudePersonalAcpDefault(context);
  if (cli == CliTool.codex) return readCodexPersonalAcpDefault(context);
  return false;
}
