import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../widgets/app_toast/app_toast.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/chat/member_input_ready_wait.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/expert_hub_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../cubits/workbench/workbench_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/failed_message_record.dart';
import '../../../models/landing_launch_context.dart';
import '../../../models/launch_security_policy.dart';
import '../../../models/simple_launch_identity.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/expert_hub/expert_hub_recent_store.dart';
import '../../../services/expert_hub/expert_landing_preflight.dart';
import '../../../services/expert_hub/expert_member_resolver.dart';
import '../../../utils/workspace/landing_draft_resolver.dart';
import '../../../utils/team/team_member_naming.dart';
import '../../../utils/logging/logger.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../chat/session_history_review_submit.dart';
import '../home_workspace_route.dart';

const _uuid = Uuid();

void leaveWorkspaceManagementRoute(BuildContext context) {
  final current = GoRouterState.of(context).uri.toString();
  final next = HomeWorkspaceRoute.locationWithoutManage(current);
  if (current == next) return;
  context.go(next);
}

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

/// Best-effort rename of an untitled session from the landing prompt, before
/// connect/delivery. A title-write failure must not block the launch.
Future<void> applyLandingPromptTitleBestEffort({
  required ChatCubit chatCubit,
  required String sessionId,
  required String prompt,
}) async {
  try {
    await chatCubit.applyFirstPromptTitle(sessionId, prompt);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'applyLandingPromptTitleBestEffort',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Opens a persisted session in a workspace tab.
///
/// [connectImmediatelyOverride] forces the choice (duplicate flow always
/// connects immediately); null defers to the user preference.
Future<void> openWorkspaceSessionTab(
  BuildContext context,
  Workspace workspace,
  AppSession session, {
  String? tabScopeId,
  bool? connectImmediatelyOverride,
}) async {
  leaveWorkspaceManagementRoute(context);
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
  final connectImmediately =
      connectImmediatelyOverride ??
      context
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
  if (status != SessionOpenStatus.opened) return;
  // ensureTab will not override an active run/shell/file tab.
  final sessionId = context.read<ChatCubit>().activeTab?.info.id.trim() ?? '';
  if (sessionId.isNotEmpty) {
    context.read<WorkbenchCubit>().openSession(
      workspace.workspaceId,
      sessionId,
    );
  }
}

/// Opens the Chat pane (new chat) for [tabScopeId] without closing open session tabs.
Future<void> showWorkspaceComposeLanding(
  BuildContext context,
  Workspace workspace, {
  required String tabScopeId,
  String? initialText,
  String? referencedSessionId,
}) async {
  leaveWorkspaceManagementRoute(context);
  final chat = context.read<ChatCubit>();
  if (chat.tabStore.activeWorkspaceId != tabScopeId) {
    chat.setActiveWorkspace(tabScopeId);
  }
  chat.enterNewChat(
    tabScopeId,
    initialText: initialText,
    referencedSessionId: referencedSessionId,
  );
}

/// Opens the workspace Landing with a prompt that points the new conversation
/// at [session]'s persisted directory. The source session and its runtime are
/// not modified or copied; the current Landing launch configuration remains
/// the source of truth for the new conversation.
Future<void> referenceWorkspaceSession(
  BuildContext context,
  AppSession session,
) async {
  try {
    final chat = context.read<ChatCubit>();
    final fs = await context.read<SessionRepository>().fs();
    final workspace = chat.state.workspaces.firstWhereOrNull(
      (item) => item.workspaceId == session.workspaceId,
    );
    if (!context.mounted || workspace == null) {
      throw StateError('workspace not found: ${session.workspaceId}');
    }
    final path = fs.layout.sessionDir(session.workspaceId, session.sessionId);
    await showWorkspaceComposeLanding(
      context,
      workspace,
      tabScopeId: session.workspaceId,
      initialText: '审查并继续完成该会话: $path',
      referencedSessionId: session.sessionId,
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'referenceWorkspaceSession',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: context.l10n.referenceConversationFailed,
        variant: TpToastVariant.error,
      );
    }
  }
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

  await showWorkspaceComposeLanding(context, workspace, tabScopeId: tabScopeId);
}

/// Creates a conversation from Chat, connects like automation dispatch, and
/// delivers [message] to the member PTY.
///
/// [launch] is the sole source of launch intent (preset, team, identity, mode).
///
/// Returns true only after terminal delivery completes successfully.
///
/// [onSessionOpened] fires once the session tab is staged, before the (possibly
/// minutes-long) connect + deliver phase, so hosts such as the Selection →
/// Ask AI dialog can dismiss themselves without waiting for delivery.
Future<bool> submitWorkspaceLandingMessage(
  BuildContext context,
  Workspace workspace, {
  required LandingLaunchContext launch,
  required String message,
  String? workingDirectory,
  String? expertKey,
  SessionPurpose purpose = SessionPurpose.normal,
  String workflowId = '',
  void Function(String sessionId)? onSessionOpened,
}) async {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return false;

  final chatCubit = context.read<ChatCubit>();
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
    if (!context.mounted) return false;
    if (resolved == null) {
      AppToast.show(
        context,
        message: l10n.expertHubNotFound,
        variant: TpToastVariant.warning,
      );
      return false;
    }
  }

  final simpleIdentity = isPersonal
      ? _resolveSimpleLaunchIdentity(
          context,
          presetId: launch.presetId,
          cli: launch.cli,
          provider: launch.provider,
          model: launch.model,
          effort: launch.effort,
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
      launchSecurityPolicy: LaunchSecurityPolicyOverride.fromPolicy(
        launch.launchSecurityPolicy,
      ),
    ),
    // Default preference keeps Chat; coordinator forces Terminal when false.
    preserveWorkbenchView: !switchToTerminal,
    purpose: purpose,
    workflowId: workflowId,
  );
  if (status == null) return false;
  if (status != SessionOpenStatus.opened) {
    if (context.mounted) {
      _handleSessionOpenStatus(
        context,
        status,
        blockedMixedMessage: l10n.mixedWorkspaceCreateSessionBlocked,
      );
    }
    return false;
  }

  // Landing unmounts ChatPage while a Run tab (启动配置) may still be active;
  // ensureTab does not steal focus from run/shell/file — select explicitly.
  if (context.mounted) {
    context.read<WorkbenchCubit>().openSession(
      liveWorkspace.workspaceId,
      plannedSessionId,
    );
  }

  if (trimmedExpert.isNotEmpty) {
    unawaited(ExpertHubRecentStore().touch(trimmedExpert));
  }

  onSessionOpened?.call(plannedSessionId);

  // Opening the session exits new-chat mode and unmounts [WorkspaceChatPane].
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
    return false;
  }

  // Landing inject bypasses FirstUserLineCapture (keyboard path only); rename
  // before connect so the tab title appears while the session is still launching.
  await applyLandingPromptTitleBestEffort(
    chatCubit: chatCubit,
    sessionId: session.sessionId,
    prompt: trimmed,
  );

  final memberId = await _resolveLandingMemberId(
    chatCubit: chatCubit,
    session: session,
    workspace: liveWorkspace,
    isPersonal: isPersonal,
    team: team,
  );

  final historyMemberId = isPersonal
      ? ''
      : (_teamLead(team)?.id ?? 'team-lead');
  FailedMessageRecord? pendingRecord;
  if (!switchToTerminal) {
    pendingRecord = await chatCubit.persistHistoryPending(
      workspaceId: liveWorkspace.workspaceId,
      sessionId: session.sessionId,
      memberId: historyMemberId,
      text: trimmed,
    );
  }

  return chatCubit.withOperatorDeliveryInFlight(session.sessionId, () async {
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
      if (pendingRecord != null) {
        await chatCubit.markHistoryPendingFailed(
          workspaceId: liveWorkspace.workspaceId,
          sessionId: session.sessionId,
          memberId: historyMemberId,
          record: pendingRecord,
        );
      }
      if (context.mounted) {
        AppToast.show(
          context,
          message: l10n.homeWorkspaceNewConversation,
          variant: TpToastVariant.error,
        );
      }
      return false;
    }

    try {
      final deliveryId = await chatCubit.sessionRuntime.deliverUserCommandToMember(
        session.sessionId,
        memberId,
        trimmed,
        directToPty: true,
      );
      if (deliveryId == null || deliveryId.trim().isEmpty) {
        if (pendingRecord != null) {
          await chatCubit.markHistoryPendingFailed(
            workspaceId: liveWorkspace.workspaceId,
            sessionId: session.sessionId,
            memberId: historyMemberId,
            record: pendingRecord,
          );
        }
        appLogger.w(
          'submitWorkspaceLandingMessage: terminal submit unconfirmed '
          'session=${session.sessionId} member=$memberId',
        );
        if (context.mounted) {
          AppToast.show(
            context,
            message: l10n.homeWorkspaceNewConversation,
            variant: TpToastVariant.error,
          );
        }
        return false;
      }
      // Pending bubble stays until transcript reconcile — do not clear here.
      return true;
    } on Object catch (error, stackTrace) {
      if (pendingRecord != null) {
        await chatCubit.markHistoryPendingFailed(
          workspaceId: liveWorkspace.workspaceId,
          sessionId: session.sessionId,
          memberId: historyMemberId,
          record: pendingRecord,
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
      return false;
    }
  });
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
    await chatCubit.memberMaterializer.ensureMemberInputReady(
      session.sessionId,
      memberId,
      directToPty: true,
    );
    return true;
  } on MemberInputReadyException catch (error) {
    appLogger.w(
      'submitWorkspaceLandingMessage: '
      '${error.failure == MemberInputReadyFailure.timedOut ? 'composer wait cap' : 'composer wait dead'} '
      'session=${session.sessionId} member=$memberId',
    );
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
  SessionPurpose purpose = SessionPurpose.normal,
  String workflowId = '',
}) async {
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final l10n = context.l10n;
  final team = isPersonal ? null : _teamProfileById(context, sessionTeamId);

  final identity = isPersonal
      ? (simpleIdentity ??
            await _resolvePersonalLaunchIdentity(
              context,
              workspace: workspace,
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
        purpose: purpose,
        workflowId: workflowId,
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
  String? provider,
  String? model,
  String? effort,
  String? expertKey,
}) {
  return resolveLandingSimpleLaunchIdentity(
    presets: context.read<CliPresetsCubit>().state.presets,
    presetId: presetId,
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    expertKey: expertKey,
  );
}

Future<SimpleLaunchIdentity> _resolvePersonalLaunchIdentity(
  BuildContext context, {
  required Workspace workspace,
  CliTool? cli,
  String? expertKey,
}) async {
  final presets = context.read<CliPresetsCubit>().state.presets;
  final draft = await resolveLandingDraft(
    workspaceId: workspace.workspaceId,
    simpleModeDefaultFullAccess: context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .simpleModeDefaultFullAccess,
  );
  final seeded = seedLandingDraftPresetDefault(draft, presets);
  return resolveLandingSimpleLaunchIdentity(
    presets: presets,
    presetId: seeded.presetId,
    cli: cli ?? seeded.cli,
    provider: seeded.provider,
    model: seeded.model,
    effort: seeded.effort,
    expertKey: expertKey ?? seeded.expertKey,
  );
}
