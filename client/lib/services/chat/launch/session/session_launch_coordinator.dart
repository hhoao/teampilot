import 'package:uuid/uuid.dart';

import '../../session/chat_tab_store.dart';
import '../../session/session_create_request.dart';
import '../../session/session_open_request.dart';
import '../../session/session_open_status.dart';
import '../../session/session_persist_params.dart';
import '../session_launch_host.dart';
import '../../../../models/app_session.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../repositories/session_repository.dart';
import '../../../event/event_publisher.dart';
import '../../../event/session_lifecycle_event.dart';
import 'session_member_cli_locks.dart';
import 'team_session_member_plan.dart';
import '../../../../utils/logging/logger.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../connect/session_connect_job.dart';
import '../connect/session_connect_scheduler.dart';
import '../connect/launch_generation_store.dart';
import 'session_tab_surface_coordinator.dart';
import 'session_launch_open_validator.dart';
import 'session_launch_workspace_index.dart';
import 'session_provisional_builder.dart';

typedef OpenMemberIntent =
    Future<void> Function(
      TeamProfile team,
      TeamMemberConfig member, {
      SessionRepository? repo,
      String? workspaceCwd,
    });

/// Intent operations consumed by launch callers and default materialization.
abstract interface class SessionLaunchIntentPort {
  Future<SessionOpenStatus> createAndOpen(SessionCreateRequest request);

  Future<SessionOpenStatus> open(
    SessionOpenRequest request, {
    LaunchReason reason = LaunchReason.openExisting,
    bool waitForCompletion = false,
  });

  Future<void> openMember(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  });
}

/// Existing-tab reconnect intent used by SSH profile changes.
abstract interface class SessionReconnectIntentPort {
  Future<void> reconnectTab(
    String sessionId,
    Iterable<SessionOpenRequest> requests,
  );
}

/// Coordinates create/open intent and emits immutable connect jobs.
class SessionLaunchCoordinator
    implements SessionLaunchIntentPort, SessionReconnectIntentPort {
  SessionLaunchCoordinator({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required SessionTabSurfaceCoordinator tabSurface,
    required SessionConnectSchedulerPort scheduler,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    Uuid uuid = const Uuid(),
    OpenMemberIntent? openMemberIntent,
    LaunchGenerationStore? generations,
  }) : _host = host,
       _tabStore = tabStore,
       _tabSurface = tabSurface,
       _scheduler = scheduler,
       _workspaceIndex = workspaceIndex,
       _uuid = uuid,
       _openMemberIntent = openMemberIntent,
       _generations = generations ?? LaunchGenerationStore();

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final SessionTabSurfaceCoordinator _tabSurface;
  final SessionConnectSchedulerPort _scheduler;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final Uuid _uuid;
  final OpenMemberIntent? _openMemberIntent;
  final LaunchGenerationStore _generations;

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex().byId(workspaceId);

  @override
  Future<SessionOpenStatus> createAndOpen(SessionCreateRequest request) async {
    appLogger.d(
      '[session-launch] coordinator create start '
      'workspace=${request.workspace.workspaceId} personal=${request.isPersonal}',
    );
    if (!request.isPersonal &&
        (request.team == null || request.member == null)) {
      return SessionOpenStatus.missingTeamMember;
    }

    final sessionTeamId = request.isPersonal
        ? ''
        : (request.team?.id ?? '').trim();
    final rosterMembers = request.isPersonal
        ? const <TeamMemberConfig>[]
        : runtimeRosterMembers(request.team!);
    if (!request.isPersonal) {
      final team = request.team!;
      final workspace = request.workspace;
      if (workspaceNeedsMixedPlacementInit(
        folders: workspace.folders,
        teamId: team.id,
        initializedByTeam: workspace.memberPlacementInitializedByTeam,
      )) {
        return SessionOpenStatus.blockedMixedMemberTargets;
      }
      final valid = rosterMembers.where((member) => member.isValid).toList();
      final targets = rememberedMemberTargets(
        workspace.memberTargetsByTeam,
        sessionTeamId,
      );
      final mustValidateLead =
          targets.isNotEmpty ||
          workspaceTopologyOf(workspace.folders) == WorkspaceTopology.mixed;
      if (mustValidateLead &&
          !leadPlacementValid(
            folders: workspace.folders,
            members: valid,
            targets: targets,
          )) {
        return SessionOpenStatus.blockedMixedMemberTargets;
      }
    }

    final fixedId = request.fixedSessionId?.trim();
    final sessionId = fixedId != null && fixedId.isNotEmpty
        ? fixedId
        : _uuid.v4();
    final workflowId = request.workflowId.trim();
    if (request.purpose == SessionPurpose.teamGeneration &&
        !isValidTeamGenerationWorkflowId(workflowId)) {
      throw ArgumentError.value(
        workflowId,
        'workflowId',
        'teamGeneration sessions require a valid workflow id',
      );
    }

    var provisional = buildProvisionalSession(
      sessionId: sessionId,
      workspace: request.workspace,
      isPersonal: request.isPersonal,
      usesPosixPaths: _host.lifecycle.storage.usesPosixPaths,
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
      sessionTeamId: sessionTeamId,
      expertKey: request.expertKey,
      home: _host.lifecycle.currentHome,
      purpose: request.purpose,
      workflowId: workflowId,
    );
    if (!request.isPersonal && request.team != null) {
      final title = request.emptyDisplayTitleFallback.trim();
      if (title.isNotEmpty) {
        provisional = provisional.copyWith(display: title);
      }
      try {
        final memberClis = resolveSessionMemberCliLocks(
          team: request.team!,
          rosterMembers: rosterMembers,
          globalPresets: _host.lifecycle.globalPresets,
        );
        final plan = buildTeamSessionMemberPlan(
          workspace: request.workspace,
          teamId: sessionTeamId,
          rosterMembers: rosterMembers,
          memberClis: memberClis,
        );
        provisional = provisional.copyWith(
          members: plan.members,
          memberTargets: plan.memberTargets,
        );
      } on StateError catch (error) {
        if (error.message == 'lead_placement_invalid' ||
            error.message == 'mixed_workspace_member_placement_uninitialized') {
          return SessionOpenStatus.blockedMixedMemberTargets;
        }
        rethrow;
      }
    }

    _host.appendSessionSnapshot(provisional);
    EventPublisher.instance.dispatchSessionLifecycle(
      SessionLifecycleEvent.sessionSpawned(
        sessionId: sessionId,
        workspaceId: request.workspace.workspaceId,
        timestamp: DateTime.now(),
      ),
    );
    final status = await open(
      SessionOpenRequest(
        session: provisional,
        workspace: request.workspace,
        team: request.team,
        member: request.member,
        repo: request.repo,
        emptyDisplayTitleFallback: request.emptyDisplayTitleFallback,
        preserveWorkbenchView: request.preserveWorkbenchView,
        persistParams: SessionPersistParams(
          sessionTeamId: sessionTeamId,
          purpose: request.purpose,
          workflowId: workflowId,
          rosterMembers: request.isPersonal ? const [] : rosterMembers,
          cli: request.cli,
          simpleIdentity: request.simpleIdentity,
          workingDirectory: request.workingDirectory,
          expertKey: request.expertKey,
          continueOverrides: request.continueOverrides,
        ),
      ),
      reason: LaunchReason.create,
    );
    if (status == SessionOpenStatus.opened) {
      EventPublisher.instance.dispatchSessionLifecycle(
        SessionLifecycleEvent.sessionStarted(
          sessionId: sessionId,
          workspaceId: request.workspace.workspaceId,
          timestamp: DateTime.now(),
        ),
      );
    }
    return status;
  }

  @override
  Future<SessionOpenStatus> open(
    SessionOpenRequest request, {
    LaunchReason reason = LaunchReason.openExisting,
    bool waitForCompletion = false,
  }) async {
    final session = request.session;
    appLogger.d(
      '[session-launch] coordinator open start '
      'session=${session.sessionId} personal=${request.isPersonal} '
      'connectImmediately=${request.connectImmediately}',
    );
    final blocked = validateSessionOpenRequest(
      request: request,
      session: session,
      workspaceById: _workspaceById,
    );
    if (blocked != null) return blocked;

    final workspace = request.workspace ?? _workspaceById(session.workspaceId);
    final connect = _shouldAutoConnect(request);
    final existing = _tabStore.getOpenTabBySessionId(session.sessionId);
    final surfaced = existing == null
        ? _tabSurface.surfaceNewTab(
            request: request,
            session: session,
            workspace: workspace,
            connect: connect,
          )
        : _tabSurface.surfaceExistingTab(
            request: request,
            existing: existing,
            workspace: workspace,
            connect: connect,
          );

    if (!request.scheduleConnect) return SessionOpenStatus.opened;

    final shouldWait = waitForCompletion || request.waitForCompletion;
    if (surfaced.connect) {
      await _scheduler.enqueue(
        _jobFor(surfaced: surfaced, request: request, reason: reason),
        waitForCompletion: shouldWait,
      );
    } else if (!request.isPersonal || shouldWait) {
      await _scheduler.enqueue(
        _jobFor(
          surfaced: surfaced,
          request: request,
          reason: reason,
          connectShell: false,
          materializeShell: true,
        ),
        waitForCompletion: shouldWait,
      );
    }
    return SessionOpenStatus.opened;
  }

  @override
  Future<void> reconnectTab(
    String sessionId,
    Iterable<SessionOpenRequest> requests,
  ) async {
    final pending = requests.toList(growable: false);
    if (pending.isEmpty) return;
    _scheduler.cancelForSession(sessionId);
    final generation = _generations.bump(sessionId);
    for (final request in pending) {
      final blocked = validateSessionOpenRequest(
        request: request,
        session: request.session,
        workspaceById: _workspaceById,
      );
      if (blocked != null) continue;
      final workspace =
          request.workspace ?? _workspaceById(request.session.workspaceId);
      await _scheduler.enqueue(
        SessionConnectJob(
          session: request.session,
          request: request,
          generation: generation,
          workspace: workspace,
          team: request.isPersonal ? null : request.team,
          member: request.isPersonal ? null : request.member,
          reason: LaunchReason.sshReconnect,
          reused: true,
          propagateErrors: true,
        ),
        waitForCompletion: true,
      );
    }
  }

  @override
  Future<void> openMember(
    TeamProfile team,
    TeamMemberConfig member, {
    SessionRepository? repo,
    String? workspaceCwd,
  }) {
    final intent = _openMemberIntent;
    if (intent == null) {
      throw StateError('Member launch intent is not configured');
    }
    return intent(team, member, repo: repo, workspaceCwd: workspaceCwd);
  }

  SessionConnectJob _jobFor({
    required SessionTabSurfaceResult surfaced,
    required SessionOpenRequest request,
    required LaunchReason reason,
    bool connectShell = true,
    bool materializeShell = false,
    bool propagateErrors = false,
  }) {
    final effectiveRequest = request.withSession(surfaced.session);
    return SessionConnectJob(
      session: surfaced.session,
      request: effectiveRequest,
      generation: surfaced.generation,
      workspace: surfaced.workspace,
      team: effectiveRequest.isPersonal ? null : effectiveRequest.team,
      member: effectiveRequest.isPersonal ? null : effectiveRequest.member,
      reason: reason,
      reused: surfaced.reused,
      connectShell: connectShell,
      materializeShell: materializeShell,
      propagateErrors: propagateErrors,
    );
  }

  bool _shouldAutoConnect(SessionOpenRequest request) {
    if (!request.connectImmediately) return false;
    if (request.isPersonal) return true;
    final team = request.team!;
    if (team.teamMode != TeamMode.mixed) return true;
    return TeamMemberNaming.isTeamLead(request.member!);
  }
}
