import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../utils/app_session_sort.dart';
import '../../../utils/team_member_naming.dart';
import '../../../utils/logger.dart';

Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session, {
  required bool isPersonal,
}) async {
  appLogger.d(
    '[session-launch] openWorkspaceSessionTab start '
    'session=${session.sessionId} workspace=${workspace.workspaceId} '
    'personal=$isPersonal launchState=${session.launchState.name}',
  );
  if (!_canLaunchWorkspaceSession(context, workspace, isPersonal: isPersonal)) {
    appLogger.w(
      '[session-launch] openWorkspaceSessionTab blocked '
      'session=${session.sessionId} personal=$isPersonal',
    );
    return;
  }

  _syncWorktreeForSession(context, session);

  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final fallback = context.l10n.defaultNewChatSessionTitle;
  final team = isPersonal ? null : context.read<LaunchProfileCubit>().state.selectedTeam;
  if (team != null) {
    unawaited(chatCubit.scheduleTeamConfigValidation(team));
  }

  final status = await chatCubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      workspace: workspace,
      team: team,
      member: isPersonal ? null : _teamLead(team),
      repo: repo,
      emptyDisplayTitleFallback: fallback,
    ),
  );
  if (!context.mounted) return;
  _handleSessionOpenStatus(
    context,
    status,
    blockedMixedMessage: context.l10n.mixedWorkspaceSessionLaunchBlocked,
  );
}

void _handleSessionOpenStatus(
  BuildContext context,
  SessionOpenStatus status, {
  required String blockedMixedMessage,
}) {
  switch (status) {
    case SessionOpenStatus.opened:
      return;
    case SessionOpenStatus.blockedMixedMemberTargets:
      AppToast.show(
        context,
        message: blockedMixedMessage,
        variant: AppToastVariant.warning,
      );
    case SessionOpenStatus.missingWorkspace:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingWorkspace,
        variant: AppToastVariant.warning,
      );
    case SessionOpenStatus.missingTeamMember:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingTeamMember,
        variant: AppToastVariant.warning,
      );
  }
}

TeamMemberConfig? _teamLead(TeamProfile? team) {
  if (team == null) return null;
  for (final member in team.members) {
    if (TeamMemberNaming.isTeamLead(member)) return member;
  }
  return null;
}

bool _canLaunchWorkspaceSession(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
}) {
  if (personalIdentityBlockedForWorkspace(
    isPersonal: isPersonal,
    folders: workspace.folders,
  )) {
    showPersonalLaunchBlockedToast(context);
    return false;
  }
  if (workspaceTopologyRequiresMemberAssignment(workspace.folders)) {
    final team = context.read<LaunchProfileCubit>().state.selectedTeam;
    if (team == null) {
      showPersonalLaunchBlockedToast(context);
      return false;
    }
  }
  return true;
}

void showPersonalLaunchBlockedToast(BuildContext context) {
  AppToast.show(
    context,
    message: context.l10n.mixedWorkspaceRequiresTeamLaunch,
    variant: AppToastVariant.warning,
  );
}

/// Makes [worktreePath] the workspace current worktree (§7) and opens a session
/// in that group — the active one when it already belongs here, otherwise the
/// most recently updated. Empty groups only switch cwd (inline CTA handles new).
Future<void> activateWorktreeGroup(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
  required String worktreePath,
  required List<AppSession> groupSessions,
}) async {
  context.read<WorktreeCubit>().setCurrentWorktree(worktreePath);
  if (groupSessions.isEmpty) return;

  final activeId = context.read<ChatCubit>().state.activeSessionId;
  AppSession? target;
  for (final session in groupSessions) {
    if (session.sessionId == activeId) {
      target = session;
      break;
    }
  }
  target ??=
      sortAppSessions(groupSessions, sort: AppSessionSort.recentlyUpdated).first;

  await openWorkspaceSessionTab(
    context,
    workspace,
    target,
    isPersonal: isPersonal,
  );
}

void _syncWorktreeForSession(BuildContext context, AppSession session) {
  try {
    context
        .read<WorktreeCubit>()
        .syncCurrentForSessionPath(session.firstFolderPath);
  } on ProviderNotFoundException {
    // Outside the workspace split pane — no worktree scope to sync.
  }
}

Future<void> createAndOpenWorkspaceConversation(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
  String sessionTeamId = '',
  String personalIdentityId = '',
  CliTool? cli,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : context.read<LaunchProfileCubit>().state.selectedTeam;

  if (!_canLaunchWorkspaceSession(context, workspace, isPersonal: isPersonal)) {
    return;
  }

  final effectiveCli = isPersonal
      ? (cli ?? _activePresetCli(context, personalIdentityId) ?? CliTool.claude)
      : null;

  if (team != null) {
    unawaited(chatCubit.scheduleTeamConfigValidation(team));
  }

  try {
    final status = await chatCubit.requestCreateAndOpenSession(
      SessionCreateRequest(
        workspace: workspace,
        isPersonal: isPersonal,
        team: team,
        member: isPersonal ? null : _teamLead(team),
        repo: repo,
        personalIdentityId: personalIdentityId,
        cli: effectiveCli,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
    if (!context.mounted) return;
    _handleSessionOpenStatus(
      context,
      status,
      blockedMixedMessage: context.l10n.mixedWorkspaceCreateSessionBlocked,
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      l10n.homeWorkspaceNewConversation,
      error: error,
      stackTrace: stackTrace,
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceNewConversation}: $error',
      variant: AppToastVariant.error,
    );
  }
}

/// Like [createAndOpenWorkspaceConversation] but pins the new session's working
/// directory to [worktreePath] (a git worktree under the workspace's repo).
Future<void> createSessionInWorktree(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
  required String worktreePath,
  String sessionTeamId = '',
  String personalIdentityId = '',
  CliTool? cli,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : context.read<LaunchProfileCubit>().state.selectedTeam;
  if (!_canLaunchWorkspaceSession(context, workspace, isPersonal: isPersonal)) {
    return;
  }
  final effectiveCli = isPersonal
      ? (cli ?? _activePresetCli(context, personalIdentityId) ?? CliTool.claude)
      : null;
  if (team != null) {
    unawaited(chatCubit.scheduleTeamConfigValidation(team));
  }
  try {
    final status = await chatCubit.requestCreateAndOpenSession(
      SessionCreateRequest(
        workspace: workspace,
        isPersonal: isPersonal,
        team: team,
        member: isPersonal ? null : _teamLead(team),
        repo: repo,
        personalIdentityId: personalIdentityId,
        cli: effectiveCli,
        workingDirectory: worktreePath,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
    if (!context.mounted) return;
    _handleSessionOpenStatus(
      context,
      status,
      blockedMixedMessage: context.l10n.mixedWorkspaceCreateSessionBlocked,
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      l10n.homeWorkspaceNewConversation,
      error: error,
      stackTrace: stackTrace,
    );
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
  final cubit = context.read<LaunchProfileCubit>();
  final byId =
      personalIdentityId.isEmpty ? null : cubit.state.byId(personalIdentityId);
  final personal = byId is PersonalProfile ? byId : cubit.activePersonal;
  final activePresetId = personal?.activePresetId;
  if (activePresetId == null || activePresetId.isEmpty) return null;
  return context.read<CliPresetsCubit>().state.presetById(activePresetId)?.cli;
}
