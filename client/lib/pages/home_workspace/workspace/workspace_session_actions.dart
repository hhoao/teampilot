import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/ai_history_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/expert_hub_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/simple_launch_identity.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/cli/preset_resolver.dart';
import '../../../services/expert_hub/expert_hub_recent_store.dart';
import '../../../services/expert_hub/expert_landing_preflight.dart';
import '../../../services/expert_hub/expert_member_resolver.dart';
import '../../../services/workbench/workbench_shell_actions.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/team/team_member_naming.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../chat/session_history_review_submit.dart';

const _uuid = Uuid();

/// Builds the [SessionOpenRequest] for opening a persisted session from the
/// sidebar / session list.
///
/// [connectImmediately] defaults to false (history review). Pass true when
/// [SessionPreferences.openExistingSessionStartsTerminal] is enabled.
SessionOpenRequest buildOpenExistingSessionRequest({
  required AppSession session,
  Workspace? workspace,
  TeamProfile? team,
  TeamMemberConfig? member,
  SessionRepository? repo,
  required String emptyDisplayTitleFallback,
  bool connectImmediately = false,
}) {
  return SessionOpenRequest(
    session: session,
    workspace: workspace,
    team: team,
    member: member,
    repo: repo,
    emptyDisplayTitleFallback: emptyDisplayTitleFallback,
    connectImmediately: connectImmediately,
  );
}

Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session, {
  String? tabScopeId,
}) async {
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
  final connectImmediately = context
      .read<SessionPreferencesCubit>()
      .state
      .preferences
      .openExistingSessionStartsTerminal;
  if (team != null) {
    unawaited(chatCubit.scheduleTeamConfigValidation(team));
  }

  final status = await chatCubit.requestOpenSession(
    buildOpenExistingSessionRequest(
      session: session,
      workspace: workspace,
      team: team,
      member: isPersonal ? null : _teamLead(team),
      repo: repo,
      emptyDisplayTitleFallback: fallback,
      connectImmediately: connectImmediately,
    ),
  );
  if (!context.mounted) return;
  _handleSessionOpenStatus(
    context,
    status,
    blockedMixedMessage: context.l10n.mixedWorkspaceSessionLaunchBlocked,
  );
  if (status != SessionOpenStatus.opened) return;

  final scopeId = tabScopeId ?? workspace.workspaceId;
  final workbench = context.read<WorkbenchCubit>();
  final tabId = WorkbenchTabId.session(session.sessionId);
  final asPreview = !connectImmediately;
  if (connectImmediately) {
    chatCubit.setSessionWorkbenchView(
      session.sessionId,
      SessionWorkbenchView.terminal,
    );
  } else {
    final existing = chatCubit.tabStore.openTabBySessionId(session.sessionId);
    // Already live: focus + pin, keep whatever Chat/Terminal view the user set.
    if (existing != null && existing.isRunning) {
      workbench.ensureTab(workspace.workspaceId, tabId, preview: false);
      return;
    }
  }
  final replaced = workbench.ensureTab(
    workspace.workspaceId,
    tabId,
    preview: asPreview,
  );
  if (!context.mounted) return;
  await WorkbenchShellActions.closeReplacedPreview(
    context: context,
    workspaceId: workspace.workspaceId,
    tabScopeId: scopeId,
    replaced: replaced,
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
        variant: TpToastVariant.warning,
      );
    case SessionOpenStatus.missingWorkspace:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingWorkspace,
        variant: TpToastVariant.warning,
      );
    case SessionOpenStatus.missingTeamMember:
      AppToast.show(
        context,
        message: context.l10n.sessionLaunchMissingTeamMember,
        variant: TpToastVariant.warning,
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
  CliTool? cli,
  String? workingDirectory,
}) async {
  // Silent create always lands on Chat (preference ignored).
  final status = await _requestCreateWorkspaceConversation(
    context,
    workspace,
    isPersonal: isPersonal,
    sessionTeamId: sessionTeamId,
    cli: cli,
    workingDirectory: workingDirectory,
    preserveWorkbenchView: true,
  );
  if (!context.mounted || status == null) return;
  _handleSessionOpenStatus(
    context,
    status,
    blockedMixedMessage: context.l10n.mixedWorkspaceCreateSessionBlocked,
  );
}

/// Opens the Chat pane (new chat) for [tabScopeId] without closing open session tabs.
Future<void> showWorkspaceComposeLanding(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
}) async {
  final chat = context.read<ChatCubit>();
  if (chat.tabStore.activeWorkspaceId != tabScopeId) {
    chat.setActiveWorkspace(tabScopeId);
  }
  chat.enterNewChat(tabScopeId);
}

/// Opens Chat with [worktreePath] pre-selected as the session cwd.
Future<void> showWorkspaceComposeLandingWithWorktree(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
  required String worktreePath,
}) async {
  final draft = await resolveLandingDraft(
    workspaceId: workspace.workspaceId,
    simpleModeDefaultFullAccess: context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .simpleModeDefaultFullAccess,
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

/// Creates a conversation from Chat, connects like automation dispatch, and
/// delivers [message] to the member PTY.
///
/// [launch] is the sole source of launch intent (preset, team, identity, mode).
Future<void> submitWorkspaceLandingMessage(
  BuildContext context,
  Workspace workspace, {
  required LandingLaunchContext launch,
  required String message,
  String? workingDirectory,
  String? expertKey,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return;

  final chatCubit = context.read<ChatCubit>();
  final aiHistoryCubit = context.read<AiHistoryCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final liveWorkspace = chatCubit.state.workspaces.firstWhere(
    (w) => w.workspaceId == workspace.workspaceId,
    orElse: () => workspace,
  );
  final isPersonal = launch.isPersonal;
  final sessionTeamId = isPersonal ? '' : (launch.teamId?.trim() ?? '');
  final team = isPersonal ? null : _teamProfileById(context, sessionTeamId);

  // Simple always carries a resolved expert key (selected or builtin default).
  final trimmedExpert = isPersonal
      ? resolveLandingSessionExpertKey(expertKey ?? launch.expertKey)
      : (expertKey?.trim() ?? launch.expertKey?.trim() ?? '');
  if (isPersonal) {
    final resolved = await ExpertMemberResolver.resolveMember(
      key: trimmedExpert,
      hubState: context.mounted ? context.read<ExpertHubCubit>().state : null,
    );
    if (!context.mounted) return;
    if (resolved == null) {
      AppToast.show(
        context,
        message: l10n.expertHubNotFound,
        variant: TpToastVariant.warning,
      );
      return;
    }
  }

  final simpleIdentity = isPersonal
      ? _resolveSimpleLaunchIdentity(
          context,
          presetId: launch.presetId,
          expertKey: trimmedExpert,
        )
      : null;
  final switchToTerminal = shouldSwitchToTerminalAfterChatSubmit(
    context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .chatSubmitSwitchesToTerminal,
  );
  final plannedSessionId = _uuid.v4();
  final status = await _requestCreateWorkspaceConversation(
    context,
    liveWorkspace,
    isPersonal: isPersonal,
    sessionTeamId: sessionTeamId,
    simpleIdentity: simpleIdentity,
    workingDirectory: workingDirectory,
    fixedSessionId: plannedSessionId,
    expertKey: trimmedExpert.isNotEmpty ? trimmedExpert : null,
    continueOverrides: SessionContinueOverrides(
      dangerouslySkipPermissions: launch.dangerouslySkipPermissions,
    ),
    // Default preference keeps Chat; coordinator forces Terminal when false.
    preserveWorkbenchView: !switchToTerminal,
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

  if (trimmedExpert.isNotEmpty) {
    unawaited(ExpertHubRecentStore().touch(trimmedExpert));
  }

  // Opening the session exits new-chat mode and unmounts [WorkspaceChatPane].
  // Delivery must keep going via cubits/repos captured above — not [context.mounted].

  // Stay-on-Chat: seed the optimistic bubble before connect/deliver so Chat
  // shows the user turn immediately (connect can take many seconds).
  final historyMemberId = isPersonal
      ? ''
      : (_teamLead(team)?.id ?? 'team-lead');
  if (!switchToTerminal) {
    aiHistoryCubit.seedPendingUser(
      sessionId: plannedSessionId,
      memberId: historyMemberId,
      text: trimmed,
    );
  }

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
    if (!switchToTerminal) {
      aiHistoryCubit.cancelSeedPendingUser(
        sessionId: plannedSessionId,
        text: trimmed,
      );
    }
    return;
  }

  final memberId = await _resolveLandingMemberId(
    chatCubit: chatCubit,
    session: session,
    workspace: liveWorkspace,
    isPersonal: isPersonal,
    team: team,
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
    if (!switchToTerminal) {
      aiHistoryCubit.cancelSeedPendingUser(
        sessionId: session.sessionId,
        text: trimmed,
      );
    }
    if (context.mounted) {
      AppToast.show(
        context,
        message: l10n.homeWorkspaceNewConversation,
        variant: TpToastVariant.error,
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
    // Landing inject bypasses FirstUserLineCapture (keyboard path only).
    await chatCubit.applyFirstPromptTitle(session.sessionId, trimmed);
  } on Object catch (error, stackTrace) {
    if (!switchToTerminal) {
      aiHistoryCubit.cancelSeedPendingUser(
        sessionId: session.sessionId,
        text: trimmed,
      );
    }
    appLogger.e(
      'submitWorkspaceLandingMessage',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: '${l10n.homeWorkspaceNewConversation}: $error',
        variant: TpToastVariant.error,
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
}) async {
  if (isPersonal) {
    return session.sessionId;
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
  CliTool? cli,
  SimpleLaunchIdentity? simpleIdentity,
  String? workingDirectory,
  String? fixedSessionId,
  String? expertKey,
  SessionContinueOverrides? continueOverrides,
  bool preserveWorkbenchView = false,
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : _teamProfileById(context, sessionTeamId);

  final identity = isPersonal
      ? (simpleIdentity ??
            _resolveSimpleLaunchIdentity(
              context,
              cli: cli,
              expertKey: expertKey,
            ))
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
        cli: identity?.cli,
        simpleIdentity: identity,
        workingDirectory: workingDirectory,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        fixedSessionId: fixedSessionId,
        expertKey: expertKey,
        continueOverrides: continueOverrides,
        preserveWorkbenchView: preserveWorkbenchView,
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
        variant: TpToastVariant.error,
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
  CliTool? cli,
}) => createAndOpenWorkspaceConversation(
  context,
  workspace,
  isPersonal: isPersonal,
  sessionTeamId: sessionTeamId,
  cli: cli,
  workingDirectory: worktreePath,
);

SimpleLaunchIdentity _resolveSimpleLaunchIdentity(
  BuildContext context, {
  String? presetId,
  CliTool? cli,
  String? expertKey,
}) {
  final presets = context.read<CliPresetsCubit>().state.presets;
  final preset = _presetById(presetId, presets);
  return SimpleLaunchIdentity.resolve(
    cli: cli,
    preset: preset,
    presetId: presetId,
    expertKey: expertKey,
  );
}

CliPreset? _presetById(String? id, List<CliPreset> presets) {
  final trimmed = id?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return presetById(trimmed, presets);
}
