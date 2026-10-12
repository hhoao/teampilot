import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../models/app_session.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../services/chat/session/chat_tab.dart';
import '../../../services/cli/registry/capabilities/acp_capability.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';

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

bool _memberAcpGates({
  required TeamMode teamMode,
  required String targetId,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (teamMode != TeamMode.mixed) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  if (runtimeKindOfId(targetId) != RuntimeKind.local) return false;
  if (cli == null) return false;
  return CliToolRegistry.builtIn().capability<AcpCapability>(cli) != null;
}

bool resolveMemberBindingAcp({
  required CliTool? cli,
  required TeamMode teamMode,
  required String targetId,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!_memberAcpGates(
    teamMode: teamMode,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  )) {
    return false;
  }
  if (cli == CliTool.gemini) return true;
  return requested;
}

bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  required TeamProfile? team,
  required String targetId,
  bool? isAndroidOverride,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpGates(
    teamMode: team?.teamMode ?? TeamMode.native,
    targetId: targetId,
    cli: cli,
    isAndroidOverride: isAndroidOverride,
  );
}
