import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../models/team_config.dart';

export '../../../services/chat/launch/session/member_acp_stamp.dart'
    show resolveMemberBindingAcp, shouldAttachMemberAcp, stampMemberAcp;

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

bool _personalAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) =>
    isPersonal &&
    (cli == CliTool.claude || cli == CliTool.cursor || cli == CliTool.codex) &&
    !_isAndroid(isAndroidOverride);

/// Final ACP flag for a launch: [requested] only counts for personal Claude,
/// Cursor, or Codex on desktop and is always false on Android. Gemini ACP is
/// inferred by session create.
bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    _personalAcpAllowed(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );

bool readPersonalAcpDefault(BuildContext context, CliTool? cli) {
  try {
    final prefs = context.read<SessionPreferencesCubit>().state.preferences;
    return switch (cli) {
      CliTool.claude => prefs.claudePersonalAcpDefault,
      CliTool.cursor => prefs.cursorPersonalAcpDefault,
      CliTool.codex => prefs.codexPersonalAcpDefault,
      _ => false,
    };
  } on ProviderNotFoundException {
    return cli == CliTool.claude || cli == CliTool.cursor;
  }
}

/// Current settings default for "personal Claude uses ACP"; true when the
/// preferences cubit is not in scope (matches [SessionPreferences] default).
bool readClaudePersonalAcpDefault(BuildContext context) =>
    readPersonalAcpDefault(context, CliTool.claude);

bool readCodexPersonalAcpDefault(BuildContext context) =>
    readPersonalAcpDefault(context, CliTool.codex);

LaunchSecurityPolicy readAcpPermissionDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .acpPermissionDefault;
  } on ProviderNotFoundException {
    return LaunchSecurityPolicy.fullAccess;
  }
}
