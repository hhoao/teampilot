import '../../utils/logging/logger.dart';
import 'models/team_generation_job.dart';
import 'team_generation_job_store.dart';
import 'team_generation_session_port.dart';
import 'team_generation_recovery_port.dart';

/// Recovery actions per job state (plan Task 13 step 7 matrix).
enum RecoveryAction {
  cancelOrphanPrecommit,
  reopenBuilder,
  commitForwardRetainBuilder,
  commitForward,
  launchForward,
  cleanupForward,
  deferCleanup,
  markIntegrityError,
}

/// Idempotent post-finalize effects used by bootstrap recovery.
abstract interface class TeamGenerationRecoveryForwarder {
  Future<void> commitForward(
    TeamGenerationJob job, {
    required bool retainBuilder,
  });

  Future<void> launchForward(TeamGenerationJob job);

  Future<void> cleanupForward(TeamGenerationJob job);
}

/// Bootstrap scan and pre-/post-commit recovery policy.
///
/// No destructive guessing: malformed or cross-workspace references are
/// retained and flagged; the destination and profile are never deleted.
final class TeamGenerationRecoveryService
    implements TeamGenerationRecoveryPort {
  TeamGenerationRecoveryService({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationSessionPort sessionPort,
    required TeamGenerationRecoveryForwarder forwarder,
  }) : _jobStore = jobStore,
       _sessionPort = sessionPort,
       _forwarder = forwarder;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSessionPort _sessionPort;
  final TeamGenerationRecoveryForwarder _forwarder;

  /// Observations recorded for tests and diagnostics.
  final observed = <(String, RecoveryAction)>[];

  @override
  Future<void> recoverAll(Iterable<String> workspaceIds) async {
    for (final workspaceId in workspaceIds) {
      await recoverWorkspace(workspaceId);
    }
  }

  /// Recovers all workflows in one workspace (used by the app bootstrap per
  /// workspace directory scan).
  @override
  Future<void> recoverWorkspace(String workspaceId) async {
    List<TeamGenerationJob> jobs;
    try {
      jobs = await _jobStore.listAll(workspaceId);
    } on Object catch (e) {
      appLogger.w('[team-generation] recovery scan failed: $e');
      return;
    }
    for (final job in jobs) {
      try {
        await _recover(job);
      } on Object catch (e) {
        appLogger.w(
          '[team-generation] recovery failed for ${job.workflowId}: $e',
        );
      }
    }
  }

  Future<void> _recover(TeamGenerationJob job) async {
    if (job.isTerminal) return;

    // Integrity: builder/workspace links must match before acting.
    if (job.builderSessionId.isEmpty ||
        job.workspaceId.isEmpty ||
        job.workflowId.isEmpty) {
      observed.add((job.workflowId, RecoveryAction.markIntegrityError));
      await _jobStore.mutate(job.workspaceId, job.workflowId, (current) {
        return current.copyWith(
          error: const TeamGenerationJobError(code: 'recovery_integrity_error'),
        );
      });
      return;
    }

    final profileSucceeded = _succeeded(job, 'profile');
    final finalizeAccepted = _succeeded(job, 'finalizeAccepted');
    final flushSucceeded = _succeeded(job, 'finalizeResponseFlushed');

    final action = _policy(
      job: job,
      profileSucceeded: profileSucceeded,
      finalizeAccepted: finalizeAccepted,
      flushSucceeded: flushSucceeded,
    );
    observed.add((job.workflowId, action));

    switch (action) {
      case RecoveryAction.cancelOrphanPrecommit:
        await _jobStore.beginCancel(job.workspaceId, job.workflowId);
      case RecoveryAction.reopenBuilder:
        final existing = await _sessionPort.sessionById(job.builderSessionId);
        if (existing == null) {
          await _jobStore.beginCancel(job.workspaceId, job.workflowId);
        } else {
          await _sessionPort.open(job.builderSessionId);
          await _recoverBuilderKickoff(job);
        }
      case RecoveryAction.commitForwardRetainBuilder:
        final builder = await _sessionPort.sessionById(job.builderSessionId);
        if (builder != null) await _sessionPort.open(job.builderSessionId);
        await _forwarder.commitForward(job, retainBuilder: true);
      case RecoveryAction.commitForward:
        final current = job.phase == TeamGenerationPhase.failed
            ? await _jobStore.resumeFailed(job.workspaceId, job.workflowId)
            : job;
        await _forwarder.commitForward(current, retainBuilder: false);
      case RecoveryAction.launchForward:
        await _forwarder.launchForward(job);
      case RecoveryAction.cleanupForward:
        await _forwarder.cleanupForward(job);
      case RecoveryAction.deferCleanup:
        break;
      case RecoveryAction.markIntegrityError:
        break;
    }
  }

  RecoveryAction _policy({
    required TeamGenerationJob job,
    required bool profileSucceeded,
    required bool finalizeAccepted,
    required bool flushSucceeded,
  }) {
    if (job.phase == TeamGenerationPhase.failed) {
      return profileSucceeded
          ? RecoveryAction.commitForward
          : RecoveryAction.deferCleanup;
    }
    if (profileSucceeded) {
      if (!_succeeded(job, 'destination')) {
        return RecoveryAction.launchForward;
      }
      return RecoveryAction.cleanupForward;
    }
    if (finalizeAccepted) {
      return flushSucceeded
          ? RecoveryAction.commitForward
          : RecoveryAction.commitForwardRetainBuilder;
    }
    final builderExists = job.builderSessionId.isNotEmpty;
    return builderExists
        ? RecoveryAction.reopenBuilder
        : RecoveryAction.cancelOrphanPrecommit;
  }

  bool _succeeded(TeamGenerationJob job, String key) =>
      job.receipts[key]?.state == TeamGenerationReceiptState.succeeded;

  /// Replays the one durable builder kickoff only when its receipt is absent.
  /// The stable delivery id lets history and PTY delivery recover a crash
  /// between either side effect and the receipt write without re-submitting.
  Future<void> _recoverBuilderKickoff(TeamGenerationJob job) async {
    if (_succeeded(job, 'builderKickoff')) return;
    final sessionId = job.builderSessionId;
    final kickoff = buildTeamGenerationKickoff(job.originalPrompt);
    final kickoffId = teamGenerationStableId(
      'teamgen-kickoff-',
      job.workflowId,
    );
    await _sessionPort.select(sessionId);
    await _sessionPort.waitForInputReady(
      sessionId,
      sessionId,
      directToPty: true,
    );
    await _sessionPort.persistHistoryPending(
      sessionId,
      sessionId,
      kickoff,
      deliveryId: kickoffId,
    );
    final result = await _sessionPort.deliverTracked(
      sessionId,
      sessionId,
      kickoff,
      directToPty: true,
      deliveryId: kickoffId,
    );
    if (!result.submitted) {
      throw StateError('team-generation recovery builder kickoff failed');
    }
    await _jobStore.mutate(job.workspaceId, job.workflowId, (current) {
      return current.copyWith(
        phase: TeamGenerationPhase.planning,
        receipts: {
          ...current.receipts,
          'builderKickoff': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
            value: kickoffId,
          ),
        },
      );
    });
  }
}
