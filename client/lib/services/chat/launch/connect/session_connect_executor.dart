import 'dart:async';

import '../../../../models/app_session.dart';
import '../../../../models/team_config.dart';
import 'connect_shell_result.dart';
import '../../../terminal/terminal_session.dart';
import '../../../../utils/logging/logger.dart';
import '../../session/chat_tab.dart';
import 'session_connect_job.dart';
import 'session_connect_scheduler.dart';
import 'session_shell_connect_port.dart';

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

  /// Terminal-less ACP chat session: attach the ACP chat runtime instead of
  /// a shell. ContributeLaunch still runs inside attach; roster, TeamBus,
  /// and PTY shell stages are skipped. Returns true when the job is fully
  /// handled.
  Future<bool> attachAcpRuntime(SessionConnectJob job, AppSession session);

  /// Mixed-seat ACP after TeamBus staging. False means the executor should
  /// keep the PTY path.
  Future<bool> attachMemberAcpRuntime(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  );

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
  final SessionShellConnectPort shellConnector;
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
      // Deferred terminal-less ACP tab (open-existing with "start terminal on
      // open" off): staging above is enough. The ACP attach below spawns the
      // adapter process and replays `session/load`, so it must wait for the
      // first send — opening a tab to read history costs no agent process.
      if (!job.connectShell && isAcpChatSession(activeSession)) return;
      // Terminal-less ACP chat session: attach the ACP runtime (which runs
      // the same simple contributeLaunch as PTY) and skip the PTY shell.
      if (isAcpChatSession(activeSession)) {
        final handled = await preparation.attachAcpRuntime(job, activeSession);
        if (handled) return;
        if (!preparation.isValid(job)) return;
      }
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
      // Member id is recorded before attach so a throw settles the waiter
      // without starting a shell. False falls through to PTY.
      attachedMemberId = resolved.member.id;
      if (await preparation.attachMemberAcpRuntime(
        job,
        activeSession,
        resolved,
      )) {
        if (preparation.isValid(job)) {
          await onResult?.call(
            job,
            activeSession,
            resolved,
            ConnectShellResult.attached,
          );
        }
        return;
      }
      attachedMemberId = null;
      final shell = preparation.shellForLaunch(job, activeSession, resolved);
      attachedMemberId = resolved.member.id;
      attachmentStarted = true;
      final result = await shellConnector.connect(
        sessionId: job.sessionId,
        session: activeSession,
        shell: shell,
        repo: job.request.repo,
        launched: activeSession.launchState == AppSessionLaunchState.started,
        team: resolved.team,
        member: resolved.member,
        workspace: job.workspace,
      );
      if (result == ConnectShellResult.failed) {
        preparation.markConnectFailed(job, attachedMemberId);
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
      } else if (attachedMemberId != null) {
        preparation.markConnectFailed(job, attachedMemberId);
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
