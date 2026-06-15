import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/project_profile_cubit.dart';
import '../../../cubits/team_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';

Future<void> openProjectSessionTab(
  BuildContext context,
  AppProject project,
  AppSession session,
) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final fallback = context.l10n.defaultNewChatSessionTitle;
  final isPersonal = project.teamId.isEmpty;

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

  final team = context.read<TeamCubit>().state.selectedTeam;
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
  AppProject project, {
  CliTool? cli,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final isPersonal = project.teamId.isEmpty;
  final team = isPersonal ? null : context.read<TeamCubit>().state.selectedTeam;
  final teamId = isPersonal ? '' : (team?.id ?? project.teamId);

  final effectiveCli = isPersonal
      // TODO: migrate to presets — was profile?.cli
      ? (cli ?? CliTool.claude)
      : null;

  try {
    final session = await chatCubit.createSession(
      project.projectId,
      repo,
      sessionTeamId: teamId,
      rosterMembers: isPersonal ? const [] : (team?.members ?? const []),
      cli: effectiveCli,
    );
    if (!context.mounted) return;
    await openProjectSessionTab(context, project, session);
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceNewConversation}: $error',
      variant: AppToastVariant.error,
    );
  }
}
