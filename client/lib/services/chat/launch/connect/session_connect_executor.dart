import 'dart:async';

import '../../../../models/app_session.dart';
import '../../../../models/team_config.dart';
import '../contracts/connect_shell_result.dart';
import '../../../terminal/terminal_session.dart';
import '../../../../utils/logging/logger.dart';
import 'session_connect_job.dart';
import 'session_connect_scheduler.dart';
import 'session_shell_connector.dart';

typedef ResolvedLaunchMembers = ({
  TeamProfile? team,
  TeamMemberConfig member,
  CliTool cli,
});

/// Application-owned preparation steps required before shell attachment.
abstract interface class SessionConnectPreparationPort {
  Future<AppSession> persist(SessionConnectJob job);

  Future<AppSession?> ensureReady(SessionConnectJob job, AppSession session);

  Future<ResolvedLaunchMembers> resolveMember(
    SessionConnectJob job,
    AppSession session,
  );

  Future<void> installTeamRuntime(
    SessionConnectJob job,
    AppSession session,
    TeamProfile? team,
  );

  Future<void> markDeferredReady(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  );

  /// Releases a member materialization waiter when shell attachment fails.
  void markConnectFailed(SessionConnectJob job, String memberId);

  TerminalSession shellForLaunch(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  );

  bool isValid(SessionConnectJob job);

  void rollback(SessionConnectJob job, AppSession session);
}

/// Executes the shared preparation and shell-attachment workflow for one job.
class SessionConnectExecutor implements SessionConnectExecutorPort {
  SessionConnectExecutor({
    required this.preparation,
    required this.shellConnector,
    this.onResult,
  });

  final SessionConnectPreparationPort preparation;
  final SessionShellConnector shellConnector;
  final FutureOr<void> Function(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
    ConnectShellResult result,
  )?
  onResult;

  @override
  Future<void> execute(SessionConnectJob job) async {
    var activeSession = job.session;
    var attachmentStarted = false;
    var connectFailureMarked = false;
    String? attachedMemberId;
    try {
      if (!preparation.isValid(job)) return;
      activeSession = await preparation.persist(job);
      if (!preparation.isValid(job)) return;
      activeSession =
          await preparation.ensureReady(job, activeSession) ?? activeSession;
      if (!preparation.isValid(job)) return;
      final resolved = await preparation.resolveMember(job, activeSession);
      if (!preparation.isValid(job)) return;
      await preparation.installTeamRuntime(job, activeSession, resolved.team);
      if (!preparation.isValid(job)) return;
      if (!job.connectShell) {
        if (job.materializeShell) {
          // Public deferred tabs need a materialized shell and team runtime;
          // they simply stop before attaching the shell transport.
          preparation.shellForLaunch(job, activeSession, resolved);
        }
        await preparation.markDeferredReady(job, activeSession, resolved);
        return;
      }
      final shell = preparation.shellForLaunch(job, activeSession, resolved);
      attachedMemberId = resolved.member.id;
      attachmentStarted = true;
      final result = await shellConnector.connect(
        tab: job.tab,
        session: activeSession,
        shell: shell,
        repo: job.request.repo,
        launched: activeSession.launchState == AppSessionLaunchState.started,
        team: resolved.team,
        member: resolved.member,
        workspace: job.workspace,
      );
      if (result == ConnectShellResult.failed) {
        preparation.markConnectFailed(job, attachedMemberId!);
        connectFailureMarked = true;
      }
      if (job.propagateErrors && result != ConnectShellResult.attached) {
        throw StateError('session reconnect ${result.name}');
      }
      if (preparation.isValid(job)) {
        await onResult?.call(job, activeSession, resolved, result);
      }
    } on Object catch (error, stackTrace) {
      final reportFailure = preparation.isValid(job);
      if (attachmentStarted) {
        try {
          await shellConnector.cleanupAfterFailure(
            tab: job.tab,
            sessionId: job.sessionId,
            memberId: attachedMemberId!,
            error: error,
            stackTrace: stackTrace,
            reportFailure: reportFailure,
          );
        } finally {
          if (!connectFailureMarked) {
            preparation.markConnectFailed(job, attachedMemberId!);
          }
        }
      } else if (reportFailure) {
        preparation.rollback(job, activeSession);
      }
      appLogger.e(
        '[session-launch] connect job failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (job.propagateErrors) {
        rethrow;
      }
    }
  }
}
