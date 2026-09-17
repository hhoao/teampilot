import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../cubits/chat/chat_tab_store.dart';
import '../../../cubits/chat/model/chat_state.dart';
import '../../../cubits/chat/model/chat_tab.dart';
import '../../../cubits/chat/model/session_connect_request.dart';
import '../../../cubits/chat/model/session_create_request.dart';
import '../../../cubits/chat/model/session_open_request.dart';
import '../../../cubits/chat/model/session_open_status.dart';
import '../../../cubits/chat/model/session_persist_params.dart';
import '../../../cubits/chat/session_launch_host.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../event/event_publisher.dart';
import '../../event/session_lifecycle_event.dart';
import '../../session/session_member_cli_locks.dart';
import '../../session/team_session_member_plan.dart';
import '../../terminal/terminal_session.dart';
import '../../../utils/logging/logger.dart';
import '../contracts/launch_operation.dart';
import '../contracts/launch_outcome.dart';
import '../contracts/member_connect_types.dart';
import 'session_default_materializer.dart';
import 'session_launch_open_validator.dart';
import 'session_launch_workspace_index.dart';
import 'session_provisional_builder.dart';
import '../tab/session_tab_surface_coordinator.dart';

import '../connect/member_connect_stage.dart';
import 'session_open_router.dart';

/// Routes [LaunchOperation] to the stage that implements it.
///
/// Flow A ("make this session exist") lives here as [create]; Flow B ("make a
/// member's terminal run") lives in [MemberConnectStage]; the open/validate
/// path is [SessionOpenRouter]. This class is now only the dispatcher.
class SessionLaunchPipeline {
  SessionLaunchPipeline({
    required SessionLaunchHost host,
    required ChatTabStore tabStore,
    required ChatState Function() state,
    required SessionLaunchWorkspaceIndex Function() workspaceIndex,
    required SessionTabSurfaceCoordinator tabSurface,
    required SessionOpenRouter openRouter,
    required MemberConnectStage memberConnect,
    required Uuid uuid,
  }) : _host = host,
       _tabStore = tabStore,
       _state = state,
       _workspaceIndex = workspaceIndex,
       _tabSurface = tabSurface,
       _openRouter = openRouter,
       _memberConnect = memberConnect,
       _uuid = uuid;

  final SessionLaunchHost _host;
  final ChatTabStore _tabStore;
  final ChatState Function() _state;
  final SessionLaunchWorkspaceIndex Function() _workspaceIndex;
  final SessionTabSurfaceCoordinator _tabSurface;
  final SessionOpenRouter _openRouter;
  final MemberConnectStage _memberConnect;
  final Uuid _uuid;

  Workspace? _workspaceById(String workspaceId) =>
      _workspaceIndex().byId(workspaceId);

  Future<LaunchOutcome> run(LaunchOperation operation) async {
    return switch (operation) {
      OpenSessionOperation(:final request) => _openRouter.run(request),
      CreateSessionOperation(:final request) => _runCreate(request),
      ConnectWorkspaceOperation(:final request, :final repo) =>
        _memberConnect.run(request, repo: repo),
      RestartWorkspaceOperation(:final request, :final repo) =>
        _memberConnect.restart(request, repo: repo),
      OpenMemberTabOperation(
        :final team,
        :final member,
        :final repo,
        :final workspaceCwd,
        :final scheduleTeamConfigValidation,
      ) =>
        _memberConnect.openMemberTab(
          team,
          member,
          repo: repo,
          workspaceCwd: workspaceCwd,
          scheduleTeamConfigValidation: scheduleTeamConfigValidation,
        ),
      LaunchAllMembersOperation(:final team, :final repo, :final workspaceCwd) =>
        _memberConnect.launchAllMembers(
          team,
          repo: repo,
          workspaceCwd: workspaceCwd,
        ),
    };
  }

  Future<LaunchOpened> _runCreate(SessionCreateRequest request) async {
    appLogger.d(
      '[session-launch] pipeline create start '
      'workspace=${request.workspace.workspaceId} personal=${request.isPersonal}',
    );

    if (!request.isPersonal &&
        (request.team == null || request.member == null)) {
      return LaunchOpened(SessionOpenStatus.missingTeamMember);
    }

    final sessionTeamId = request.isPersonal
        ? ''
        : (request.team?.id ?? '').trim();
    if (!request.isPersonal) {
      final team = request.team!;
      final workspace = request.workspace;
      if (workspaceNeedsMixedPlacementInit(
        folders: workspace.folders,
        teamId: team.id,
        initializedByTeam: workspace.memberPlacementInitializedByTeam,
      )) {
        return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
      }
      final valid = team.members.where((m) => m.isValid).toList();
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
        return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
      }
    }

    final fixedId = request.fixedSessionId?.trim();
    final sessionId = fixedId != null && fixedId.isNotEmpty
        ? fixedId
        : _uuid.v4();
    final requestWorkflowId = request.workflowId.trim();
    if (request.purpose == SessionPurpose.teamGeneration &&
        !isValidTeamGenerationWorkflowId(requestWorkflowId)) {
      throw ArgumentError.value(
        requestWorkflowId,
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
      workflowId: requestWorkflowId,
    );

    // Destination team sessions should show the team name immediately — the
    // emptyDisplayTitleFallback is team.name from createDestination. Generic
    // "New Chat" fallbacks stay off disk so locale can still resolve them.
    if (!request.isPersonal && request.team != null) {
      final titled = request.emptyDisplayTitleFallback.trim();
      if (titled.isNotEmpty) {
        provisional = provisional.copyWith(display: titled);
      }
    }

    // Team sessions need provisional member bindings so history loading (which
    // fires immediately after the UI mounts) can resolve session.requireBinding
    // before persistence completes asynchronously.
    if (!request.isPersonal && request.team != null) {
      try {
        final memberClis = resolveSessionMemberCliLocks(
          team: request.team!,
          rosterMembers: request.team!.members,
          globalPresets: _host.lifecycle.globalPresets,
        );
        final plan = buildTeamSessionMemberPlan(
          workspace: request.workspace,
          teamId: sessionTeamId,
          rosterMembers: request.team!.members,
          memberClis: memberClis,
        );
        provisional = provisional.copyWith(
          members: plan.members,
          memberTargets: plan.memberTargets,
        );
      } on StateError catch (e) {
        final msg = e.message;
        if (msg == 'lead_placement_invalid' ||
            msg == 'mixed_workspace_member_placement_uninitialized') {
          return LaunchOpened(SessionOpenStatus.blockedMixedMemberTargets);
        }
        rethrow;
      }
    }
    _host.appendSessionSnapshot(provisional);
    // Pure side-channel: session object now exists with a stable sessionId.
    // No dispatcher attached (tests/early startup) → no-op; never awaited.
    EventPublisher.instance.dispatchSessionLifecycle(
      SessionLifecycleEvent.sessionSpawned(
        sessionId: sessionId,
        workspaceId: request.workspace.workspaceId,
        timestamp: DateTime.now(),
      ),
    );

    final persistParams = SessionPersistParams(
      sessionTeamId: sessionTeamId,
      purpose: request.purpose,
      workflowId: requestWorkflowId,
      rosterMembers: request.isPersonal
          ? const []
          : (request.team?.members ?? const []),
      cli: request.cli,
      simpleIdentity: request.simpleIdentity,
      workingDirectory: request.workingDirectory,
      expertKey: request.expertKey,
      continueOverrides: request.continueOverrides,
    );

    final status = _tabSurface.surfaceNewTab(
      request: SessionOpenRequest(
        session: provisional,
        workspace: request.workspace,
        team: request.team,
        member: request.member,
        repo: request.repo,
        emptyDisplayTitleFallback: request.emptyDisplayTitleFallback,
        preserveWorkbenchView: request.preserveWorkbenchView,
        persistParams: persistParams,
      ),
      session: provisional,
    );
    if (status == SessionOpenStatus.opened) {
      // Pure side-channel: publish before returning the successful open.
      EventPublisher.instance.dispatchSessionLifecycle(
        SessionLifecycleEvent.sessionStarted(
          sessionId: sessionId,
          workspaceId: request.workspace.workspaceId,
          timestamp: DateTime.now(),
        ),
      );
    }
    return LaunchOpened(status);
  }

}