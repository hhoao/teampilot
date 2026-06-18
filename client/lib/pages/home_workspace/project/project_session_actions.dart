import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/identity_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/personal_identity.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';

Future<void> openProjectSessionTab(
  BuildContext context,
  Workspace project,
  AppSession session, {
  required bool isPersonal,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final fallback = context.l10n.defaultNewChatSessionTitle;

  chatCubit.selectSession(session.sessionId);

  if (isPersonal) {
    await chatCubit.openSessionTab(
      session,
      team: null,
      member: null,
      repo: repo,
      emptyDisplayTitleFallback: fallback,
    );
    return;
  }

  final team = context.read<IdentityCubit>().state.selectedTeam;
  final leads =
      team?.members.where((m) => m.id == 'team-lead').toList() ??
      const <TeamMemberConfig>[];
  final TeamMemberConfig? lead = leads.isEmpty ? null : leads.first;

  await chatCubit.openSessionTab(
    session,
    team: lead != null ? team : null,
    member: lead,
    repo: repo,
    emptyDisplayTitleFallback: fallback,
  );
}

Future<void> createAndOpenProjectConversation(
  BuildContext context,
  Workspace project, {
  required bool isPersonal,
  String sessionTeamId = '',
  String personalIdentityId = '',
  CliTool? cli,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : context.read<IdentityCubit>().state.selectedTeam;

  // A new personal conversation pins its CLI to the active preset's CLI so it
  // resumes under (and stores its transcript with) the CLI the user selected.
  // An explicit [cli] override (e.g. a per-preset "new chat" action) wins.
  final effectiveCli = isPersonal
      ? (cli ?? _activePresetCli(context, personalIdentityId) ?? CliTool.claude)
      : null;

  try {
    final session = await chatCubit.createSession(
      project.projectId,
      repo,
      sessionTeamId: isPersonal ? '' : (team?.id ?? sessionTeamId),
      personalIdentityId: isPersonal ? personalIdentityId : '',
      rosterMembers: isPersonal ? const [] : (team?.members ?? const []),
      cli: effectiveCli,
    );
    if (!context.mounted) return;
    await openProjectSessionTab(
      context,
      project,
      session,
      isPersonal: isPersonal,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceNewConversation}: $error',
      variant: AppToastVariant.error,
    );
  }
}

/// CLI of the opened personal identity's active preset, or `null` when
/// unavailable (e.g. no preset selected yet). Used to pin a new personal
/// session's CLI. Falls back to the cubit's default personal when
/// [personalIdentityId] is empty or unknown.
CliTool? _activePresetCli(BuildContext context, String personalIdentityId) {
  final cubit = context.read<IdentityCubit>();
  final byId =
      personalIdentityId.isEmpty ? null : cubit.state.byId(personalIdentityId);
  final personal = byId is PersonalIdentity ? byId : cubit.activePersonal;
  final activePresetId = personal?.activePresetId;
  if (activePresetId == null || activePresetId.isEmpty) return null;
  return context.read<CliPresetsCubit>().state.presetById(activePresetId)?.cli;
}
