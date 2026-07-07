import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/cli/preset_resolver.dart';
import '../../../services/launch/personal_launch_context_resolver.dart';
import '../../../utils/landing_draft_resolver.dart';
import '../../../utils/team_member_naming.dart';
import '../../../utils/logger.dart';
import '../../../utils/workspace_path_utils.dart';

const _uuid = Uuid();

Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session,
) async {
  final isPersonal = session.sessionTeam.trim().isEmpty;
  appLogger.d(
    '[session-launch] openWorkspaceSessionTab start '
    'session=${session.sessionId} workspace=${workspace.workspaceId} '
    'personal=$isPersonal launchState=${session.launchState.name}',
  );
  final team = await _syncSessionTeam(context, session);

  _syncWorktreeForSession(context, session);

  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final fallback = context.l10n.defaultNewChatSessionTitle;
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

TeamProfile? _teamProfileById(BuildContext context, String teamId) {
  final id = teamId.trim();
  if (id.isEmpty) return null;
  final profile = context.read<LaunchProfileCubit>().byId(id);
  return profile is TeamProfile ? profile : null;
}

Future<TeamProfile?> _syncSessionTeam(
  BuildContext context,
  AppSession session,
) async {
  final teamId = session.sessionTeam.trim();
  if (teamId.isEmpty) return null;
  final launchProfiles = context.read<LaunchProfileCubit>();
  final existing = launchProfiles.byId(teamId);
  if (existing is TeamProfile) {
    await launchProfiles.selectTeam(teamId, silent: true);
    return existing;
  }
  await launchProfiles.selectTeam(teamId, silent: true);
  final resolved = launchProfiles.byId(teamId);
  return resolved is TeamProfile ? resolved : null;
}

TeamMemberConfig? _teamLead(TeamProfile? team) {
  if (team == null) return null;
  for (final member in team.members) {
    if (TeamMemberNaming.isTeamLead(member)) return member;
  }
  return null;
}

void _syncWorktreeForSession(BuildContext context, AppSession session) {
  try {
    context.read<WorktreeCubit>().syncCurrentForSessionPath(
      session.firstFolderPath,
    );
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
  String? workingDirectory,
}) async {
  final status = await _requestCreateWorkspaceConversation(
    context,
    workspace,
    isPersonal: isPersonal,
    sessionTeamId: sessionTeamId,
    personalIdentityId: personalIdentityId,
    cli: cli,
    workingDirectory: workingDirectory,
  );
  if (!context.mounted || status == null) return;
  _handleSessionOpenStatus(
    context,
    status,
    blockedMixedMessage: context.l10n.mixedWorkspaceCreateSessionBlocked,
  );
}

/// Opens the compose landing for [tabScopeId] without closing open session tabs.
Future<void> showWorkspaceComposeLanding(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
}) async {
  final chat = context.read<ChatCubit>();
  if (chat.tabStore.activeWorkspaceId != tabScopeId) {
    chat.setActiveWorkspace(tabScopeId);
  }
  chat.enterComposeMode(tabScopeId);
}

/// Opens compose landing with [worktreePath] pre-selected as the session cwd.
Future<void> showWorkspaceComposeLandingWithWorktree(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
  required String worktreePath,
}) async {
  final draft = await resolveLandingDraft(
    workspaceId: workspace.workspaceId,
    workspace: workspace,
  );
  if (!context.mounted) return;

  final normalizedPath = normalizeWorkspacePath(worktreePath);
  await persistLandingDraft(
    workspace.workspaceId,
    draft.copyWith(workingDirectoryPath: normalizedPath),
  );
  if (!context.mounted) return;

  try {
    context.read<WorktreeCubit>().setCurrentWorktree(normalizedPath);
  } on ProviderNotFoundException {
    // Outside the workspace split pane — draft still carries the path.
  }

  await showWorkspaceComposeLanding(
    context,
    workspace,
    tabScopeId: tabScopeId,
  );
}

/// Creates a conversation from the compose landing, connects like automation
/// dispatch, and delivers [message] to the member PTY.
///
/// [launch] is the sole source of launch intent (preset, team, identity, mode).
Future<void> submitWorkspaceLandingMessage(
  BuildContext context,
  Workspace workspace, {
  required LandingLaunchContext launch,
  required String message,
  String? workingDirectory,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;

  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final liveWorkspace = chatCubit.state.workspaces.firstWhere(
    (w) => w.workspaceId == workspace.workspaceId,
    orElse: () => workspace,
  );
  final isPersonal = launch.isPersonal;
  final sessionTeamId = isPersonal ? '' : (launch.teamId?.trim() ?? '');
  final personalIdentityId = launch.personalProfileId.trim();
  final personalPresetId = launch.presetId?.trim() ?? '';
  final team = isPersonal ? null : _teamProfileById(context, sessionTeamId);

  final plannedSessionId = _uuid.v4();
  final status = await _requestCreateWorkspaceConversation(
    context,
    liveWorkspace,
    isPersonal: isPersonal,
    sessionTeamId: sessionTeamId,
    personalIdentityId: personalIdentityId,
    personalPresetId: personalPresetId.isNotEmpty ? personalPresetId : null,
    workingDirectory: workingDirectory,
    fixedSessionId: plannedSessionId,
  );
  if (status == null) return;
  if (status != SessionOpenStatus.opened) {
    if (context.mounted) {
      _handleSessionOpenStatus(
        context,
        status,
        blockedMixedMessage: l10n.mixedWorkspaceCreateSessionBlocked,
      );
    }
    return;
  }

  // Opening the session exits compose mode and unmounts [WorkspaceComposeLandingPane].
  // Delivery must keep going via cubits/repos captured above — not [context.mounted].

  final session = await _sessionById(
    chatCubit: chatCubit,
    repo: repo,
    sessionId: plannedSessionId,
    workspaceId: liveWorkspace.workspaceId,
  );
  if (session == null) {
    appLogger.w(
      'submitWorkspaceLandingMessage: session missing after open '
      'sessionId=$plannedSessionId workspace=${liveWorkspace.workspaceId}',
    );
    return;
  }

  final memberId = await _resolveLandingMemberId(
    chatCubit: chatCubit,
    session: session,
    workspace: liveWorkspace,
    isPersonal: isPersonal,
    team: team,
    personalIdentityId: personalIdentityId,
    personalPresetId: personalPresetId.isNotEmpty ? personalPresetId : null,
  );

  final connected = await _ensureLandingSessionConnected(
    chatCubit: chatCubit,
    session: session,
    memberId: memberId,
  );
  if (!connected) {
    appLogger.w(
      'submitWorkspaceLandingMessage: member not ready '
      'session=${session.sessionId} member=$memberId',
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: l10n.homeWorkspaceNewConversation,
        variant: AppToastVariant.error,
      );
    }
    return;
  }

  try {
    await chatCubit.sessionRuntime.deliverUserCommandToMember(
      session.sessionId,
      memberId,
      trimmed,
      directToPty: true,
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'submitWorkspaceLandingMessage',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: '${l10n.homeWorkspaceNewConversation}: $error',
        variant: AppToastVariant.error,
      );
    }
  }
}

Future<AppSession?> _sessionById({
  required ChatCubit chatCubit,
  required SessionRepository repo,
  required String sessionId,
  required String workspaceId,
}) async {
  final fromState = chatCubit.state.sessions
      .where((s) => s.sessionId == sessionId && s.workspaceId == workspaceId)
      .firstOrNull;
  if (fromState != null) return fromState;
  final loaded = await repo.loadSessionsForWorkspace(workspaceId);
  return loaded.where((s) => s.sessionId == sessionId).firstOrNull;
}

Future<String> _resolveLandingMemberId({
  required ChatCubit chatCubit,
  required AppSession session,
  required Workspace workspace,
  required bool isPersonal,
  required TeamProfile? team,
  required String personalIdentityId,
  String? personalPresetId,
}) async {
  if (isPersonal) {
    final resolver = PersonalLaunchContextResolver(chatCubit.lifecycle);
    final ctx = await resolver.resolve(
      session: session,
      workspace: workspace,
      personalIdentityIdOverride: personalIdentityId,
      presetIdOverride: personalPresetId ?? '',
    );
    return ctx.personalMember.id;
  }
  final lead = _teamLead(team);
  return lead?.id ?? 'team-lead';
}

Future<bool> _ensureLandingSessionConnected({
  required ChatCubit chatCubit,
  required AppSession session,
  required String memberId,
}) async {
  // requestCreateAndOpenSession already staged the tab and scheduled async
  // persist+connect. Re-opening here races that path and can connect with the
  // provisional session (empty cliTeamName) before disk persistence finishes.
  try {
    await chatCubit.memberMaterializer
        .ensureMemberInputReady(
          session.sessionId,
          memberId,
          directToPty: true,
        )
        .timeout(const Duration(seconds: 120));
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<SessionOpenStatus?> _requestCreateWorkspaceConversation(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
  String sessionTeamId = '',
  String personalIdentityId = '',
  String? personalPresetId,
  CliTool? cli,
  String? workingDirectory,
  String? fixedSessionId,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : _teamProfileById(context, sessionTeamId);

  final effectiveCli = isPersonal
      ? _resolvePersonalSessionCli(
          context,
          personalPresetId: personalPresetId,
          personalIdentityId: personalIdentityId,
          cliOverride: cli,
        )
      : null;

  if (team != null) {
    unawaited(chatCubit.scheduleTeamConfigValidation(team));
  }

  try {
    return await chatCubit.requestCreateAndOpenSession(
      SessionCreateRequest(
        workspace: workspace,
        isPersonal: isPersonal,
        team: team,
        member: isPersonal ? null : _teamLead(team),
        repo: repo,
        personalIdentityId: personalIdentityId,
        cli: effectiveCli,
        personalPresetId: personalPresetId,
        workingDirectory: workingDirectory,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        fixedSessionId: fixedSessionId,
      ),
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      l10n.homeWorkspaceNewConversation,
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: '${l10n.homeWorkspaceNewConversation}: $error',
        variant: AppToastVariant.error,
      );
    }
    return null;
  }
}

/// Pins the new session's working directory to [worktreePath] (a git worktree
/// under the workspace's repo).
Future<void> createSessionInWorktree(
  BuildContext context,
  Workspace workspace, {
  required bool isPersonal,
  required String worktreePath,
  String sessionTeamId = '',
  String personalIdentityId = '',
  CliTool? cli,
}) => createAndOpenWorkspaceConversation(
  context,
  workspace,
  isPersonal: isPersonal,
  sessionTeamId: sessionTeamId,
  personalIdentityId: personalIdentityId,
  cli: cli,
  workingDirectory: worktreePath,
);

/// Pins CLI for a new personal session.
///
/// [personalPresetId] wins when set (landing / automation). Otherwise falls
/// back to the identity's saved active preset, then [cliOverride], then Claude.
CliTool _resolvePersonalSessionCli(
  BuildContext context, {
  String? personalPresetId,
  String personalIdentityId = '',
  CliTool? cliOverride,
}) {
  final presets = context.read<CliPresetsCubit>().state.presets;
  final pinned = cliForPresetId(personalPresetId, presets);
  if (pinned != null) return pinned;
  if (cliOverride != null) return cliOverride;

  final cubit = context.read<LaunchProfileCubit>();
  final byId = personalIdentityId.isEmpty
      ? null
      : cubit.state.byId(personalIdentityId);
  final personal = byId is PersonalProfile ? byId : cubit.activePersonal;
  final activePresetId = personal?.activePresetId;
  if (activePresetId != null && activePresetId.isNotEmpty) {
    final fromProfile = cliForPresetId(activePresetId, presets);
    if (fromProfile != null) return fromProfile;
  }
  return CliTool.claude;
}
