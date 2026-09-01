import 'dart:async';

import '../../models/app_session.dart';
import '../../models/landing_launch_context.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/team_generation/team_generation_session_port.dart';
import '../../utils/logging/logger.dart';
import '../../utils/team/team_member_naming.dart';
import '../chat_cubit.dart';
import '../workbench/workbench_cubit.dart';

/// Flutter adapter implementing [TeamGenerationSessionPort] on top of
/// [ChatCubit] / [WorkbenchCubit] / repositories. Workflow services depend
/// only on the port; this is the sole consumer of the cubit layer.
final class CubitTeamGenerationSessionPort
    implements TeamGenerationSessionPort {
  CubitTeamGenerationSessionPort({
    required ChatCubit chatCubit,
    required WorkbenchCubit workbenchCubit,
    required SessionRepository sessionRepository,
  }) : _chatCubit = chatCubit,
       _workbenchCubit = workbenchCubit,
       _sessionRepository = sessionRepository;

  final ChatCubit _chatCubit;
  final WorkbenchCubit _workbenchCubit;
  final SessionRepository _sessionRepository;

  @override
  Future<SessionPortOpenResult> createBuilder({
    required Workspace workspace,
    required SimpleLaunchIdentity identity,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String workflowId,
    required String fixedSessionId,
    required String expertKey,
    String emptyDisplayTitleFallback = 'Team Builder',
    bool preserveWorkbenchView = true,
  }) async {
    final status = await _openSession(
      workspace: workspace,
      isPersonal: true,
      identity: identity,
      workingDirectory: workingDirectoryPath,
      purpose: SessionPurpose.teamGeneration,
      workflowId: workflowId,
      fixedSessionId: fixedSessionId,
      expertKey: expertKey,
      emptyDisplayTitleFallback: emptyDisplayTitleFallback,
      preserveWorkbenchView: preserveWorkbenchView,
    );
    return SessionPortOpenResult(
      status: status.name,
      sessionId: fixedSessionId,
    );
  }

  @override
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  }) async {
    final status = await _openSession(
      workspace: workspace,
      isPersonal: false,
      team: team,
      workingDirectory: workingDirectoryPath,
      purpose: SessionPurpose.normal,
      fixedSessionId: fixedSessionId,
      emptyDisplayTitleFallback: team.name,
      preserveWorkbenchView: false,
    );
    return SessionPortOpenResult(
      status: status.name,
      sessionId: fixedSessionId,
    );
  }

  @override
  Future<SessionPortOpenResult> open(String sessionId) async {
    final session = await sessionById(sessionId);
    if (session == null) {
      return const SessionPortOpenResult(status: 'missingSession');
    }
    final workspace = await _workspaceById(session.workspaceId);
    final status = await _chatCubit.requestOpenSession(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        repo: _sessionRepository,
        emptyDisplayTitleFallback: session.display.isEmpty
            ? 'New Chat'
            : session.display,
      ),
    );
    return SessionPortOpenResult(status: status.name, sessionId: sessionId);
  }

  Future<Workspace?> _workspaceById(String workspaceId) async {
    for (final workspace in _chatCubit.state.workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  Future<SessionOpenStatus> _openSession({
    required Workspace workspace,
    required bool isPersonal,
    SimpleLaunchIdentity? identity,
    TeamProfile? team,
    String? workingDirectory,
    required SessionPurpose purpose,
    String workflowId = '',
    String? fixedSessionId,
    String? expertKey,
    required String emptyDisplayTitleFallback,
    required bool preserveWorkbenchView,
  }) {
    return _chatCubit.requestCreateAndOpenSession(
      SessionCreateRequest(
        workspace: workspace,
        isPersonal: isPersonal,
        team: team,
        member: isPersonal ? null : _teamLead(team),
        repo: _sessionRepository,
        cli: identity?.cli,
        simpleIdentity: identity,
        workingDirectory: workingDirectory,
        emptyDisplayTitleFallback: emptyDisplayTitleFallback,
        fixedSessionId: fixedSessionId,
        expertKey: expertKey,
        purpose: purpose,
        workflowId: workflowId,
        preserveWorkbenchView: preserveWorkbenchView,
      ),
    );
  }

  TeamMemberConfig? _teamLead(TeamProfile? team) {
    for (final member in team?.members ?? const <TeamMemberConfig>[]) {
      if (TeamMemberNaming.isTeamLead(member)) return member;
    }
    return team?.members.firstOrNull;
  }

  @override
  Future<void> select(String sessionId) async {
    _workbenchCubit.openSession(_workspaceIdFor(sessionId), sessionId);
  }

  String _workspaceIdFor(String sessionId) {
    for (final workspace in _chatCubit.state.workspaces) {
      for (final id in workspace.sessionIds) {
        if (id == sessionId) return workspace.workspaceId;
      }
    }
    // Fallback: the active workspace (destination creation just persisted the
    // session into it).
    return _chatCubit.tabStore.activeWorkspaceId;
  }

  @override
  Future<AppSession?> sessionById(String sessionId) async {
    for (final session in _chatCubit.state.sessions) {
      if (session.sessionId == sessionId) return session;
    }
    try {
      return await _sessionRepository.findById(sessionId);
    } on Object catch (e) {
      appLogger.w('[team-generation] sessionById failed: $e');
      return null;
    }
  }

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {
    // The materializer facade routes through the existing input-ready gate.
    await _chatCubit.memberMaterializer.ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: directToPty,
    );
  }

  @override
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  }) async {
    final session = await sessionById(sessionId);
    if (session == null) {
      throw StateError('team-generation history session missing: $sessionId');
    }
    final record = await _chatCubit.persistHistoryPending(
      workspaceId: session.workspaceId,
      sessionId: sessionId,
      // Simple sessions use the unscoped history seat, exactly like landing.
      memberId: session.isSimple ? '' : memberId,
      text: text,
      deliveryId: deliveryId,
    );
    if (record == null) {
      throw StateError(
        'team-generation history seed could not persist: $sessionId',
      );
    }
  }

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async {
    // Direct-to-PTY delivery through the app-scoped durable coordinator.
    final delivery = await _chatCubit.sessionRuntime
        .deliverTrackedUserCommandToMember(
          sessionId,
          memberId,
          text,
          deliveryId: deliveryId,
        );
    return PortDeliveryOutcome(
      result: delivery.submitted ? 'submitted' : 'failed',
      deliveryState: delivery.state,
    );
  }

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async {
    try {
      final session = await sessionById(sessionId);
      if (session == null) return true;
      // Purpose guard: never delete a session that is not this workflow's
      // builder, and never the destination.
      if (session.purpose != SessionPurpose.teamGeneration ||
          session.workflowId != workflowId) {
        appLogger.w(
          '[team-generation] deleteBuilder refused: session=$sessionId '
          'purpose=${session.purpose.name} workflow=${session.workflowId}',
        );
        return false;
      }
      await _chatCubit.deleteSession(_sessionRepository, sessionId);
      return true;
    } on Object catch (e) {
      appLogger.w('[team-generation] deleteBuilder failed: $e');
      return false;
    }
  }

  @override
  Stream<PortActivity> activityStream(String sessionId) {
    // Ready = this session's pod finished launching and is not connecting.
    return _chatCubit.stream.map((_) {
      final pod = _chatCubit.podFor(sessionId);
      final ready = pod != null && !pod.phase.isLaunching;
      return PortActivity(sessionId: sessionId, readyToChat: ready);
    }).distinct();
  }
}

/// Landing kickoff text for the builder (frozen in the plan Task 13).
String buildTeamGenerationKickoff(String originalPrompt) =>
    'Build and launch the optimal TeamPilot team for the task below.\n'
    'Follow the managed Team Builder skill and use Team Composer until '
    'finalize_team_generation succeeds.\n\n'
    '$originalPrompt';

/// Landing-launch context patch after handoff (selection writer seam).
LandingLaunchContext landingContextForGeneratedTeam({
  required LandingLaunchContext previous,
  required String teamId,
}) =>
    previous.copyWith(isPersonal: false, generateLaunch: false, teamId: teamId);
