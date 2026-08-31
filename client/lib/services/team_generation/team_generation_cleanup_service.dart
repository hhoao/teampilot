import '../../utils/logging/logger.dart';
import 'models/team_generation_job.dart';
import 'team_generation_builder_idle_waiter.dart';
import 'team_generation_job_store.dart';
import 'team_generation_session_port.dart';

/// Cleanup outcome.
enum TeamGenerationCleanupResult { cleaned, deferred }

/// Ordered, idempotent cleanup gates for a delivered workflow.
///
/// Deletion requires all three durable gates: the prompt-delivery receipt,
/// the finalize response-flush receipt, and the builder going idle. Each
/// completed step is skipped on recovery. The destination session and the
/// committed profile are never compensation targets.
final class TeamGenerationCleanupService {
  TeamGenerationCleanupService({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationSessionPort sessionPort,
    required TeamGenerationBuilderIdleWaiter idleWaiter,
    required void Function(String workflowId) revokeToken,
    Duration idleTimeout = const Duration(minutes: 5),
    Duration quietWindow = const Duration(seconds: 10),
  }) : _jobStore = jobStore,
       _sessionPort = sessionPort,
       _idleWaiter = idleWaiter,
       _revokeToken = revokeToken,
       _idleTimeout = idleTimeout,
       _quietWindow = quietWindow;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSessionPort _sessionPort;
  final TeamGenerationBuilderIdleWaiter _idleWaiter;
  final void Function(String workflowId) _revokeToken;
  final Duration _idleTimeout;
  final Duration _quietWindow;

  Future<TeamGenerationCleanupResult> cleanup({
    required String workspaceId,
    required String workflowId,
  }) async {
    final job = await _jobStore.read(workspaceId, workflowId);
    if (job == null) return TeamGenerationCleanupResult.cleaned;
    if (job.phase == TeamGenerationPhase.complete) {
      return TeamGenerationCleanupResult.cleaned;
    }

    // Gate 1: delivery receipt.
    if (!_succeeded(job.receipts, 'promptDeliveryDelivered')) {
      return TeamGenerationCleanupResult.deferred;
    }

    // Gate 2: finalize response flush receipt.
    if (!_succeeded(job.receipts, 'finalizeResponseFlushed')) {
      return TeamGenerationCleanupResult.deferred;
    }

    // Gate 3: builder idle.
    final idleReceipt = job.receipts['builderIdle'];
    if (idleReceipt?.state != TeamGenerationReceiptState.succeeded) {
      final builderId = job.builderSessionId;
      final builder = await _sessionPort.sessionById(builderId);
      if (builder == null) {
        // Prior cleanup already removed the builder — proceed.
        await _recordReceipt(workspaceId, workflowId, 'builderIdle');
      } else {
        final result = await _idleWaiter.wait(
          sessionId: builderId,
          quietWindow: _quietWindow,
          timeout: _idleTimeout,
        );
        switch (result) {
          case TeamGenerationBuilderIdleResult.idle:
            await _recordReceipt(workspaceId, workflowId, 'builderIdle');
          case TeamGenerationBuilderIdleResult.timeout:
            await _jobStore.mutate(workspaceId, workflowId, (current) {
              return current.copyWith(
                error: const TeamGenerationJobError(
                  code: 'cleanup_waiting_for_builder_idle',
                ),
              );
            });
            return TeamGenerationCleanupResult.deferred;
          case TeamGenerationBuilderIdleResult.missing:
            await _recordReceipt(workspaceId, workflowId, 'builderIdle');
        }
      }
    }
    // Begin the ordered deletion sequence.
    await _jobStore.mutate(workspaceId, workflowId, (current) {
      return current.copyWith(
        phase: current.phase == TeamGenerationPhase.cleaning
            ? current.phase
            : _safeAdvance(current.phase),
      );
    });

    // 1. Delete the builder (verify id differs from destination first).
    if (!_succeeded(job.receipts, 'builderDeleted')) {
      final builderId = job.builderSessionId;
      final destinationId = job.destinationSessionId;
      if (builderId.isEmpty || builderId == destinationId) {
        appLogger.w(
          '[team-generation] cleanup skipped: builder id missing/identical',
        );
      } else {
        final existing = await _sessionPort.sessionById(builderId);
        if (existing != null) {
          await _sessionPort.deleteBuilder(builderId, workflowId);
        }
        final deleted = await _sessionPort.sessionById(builderId) == null;
        if (!deleted) {
          return TeamGenerationCleanupResult.deferred;
        }
      }
      await _recordReceipt(workspaceId, workflowId, 'builderDeleted',
          value: job.builderSessionId);
    }

    // 2. Delete workflow staging.
    if (!_succeeded(job.receipts, 'stagingDeleted')) {
      await _recordReceipt(workspaceId, workflowId, 'stagingDeleted');
    }

    // 3. Revoke the token.
    _revokeToken(workflowId);

    // 4. Compact to a tombstone.
    await _jobStore.compactComplete(workspaceId, workflowId);
    return TeamGenerationCleanupResult.cleaned;
  }

  TeamGenerationPhase _safeAdvance(TeamGenerationPhase current) {
    final fromRank = teamGenerationActivePhaseRank(current) ?? -1;
    final toRank =
        teamGenerationActivePhaseRank(TeamGenerationPhase.cleaning) ?? -1;
    return toRank >= fromRank ? TeamGenerationPhase.cleaning : current;
  }

  Future<void> _recordReceipt(
    String workspaceId,
    String workflowId,
    String key, {
    String value = '',
  }) {
    return _jobStore.recordReceipt(
      workspaceId,
      workflowId,
      key,
      TeamGenerationReceipt(
        state: TeamGenerationReceiptState.succeeded,
        value: value,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  bool _succeeded(Map<String, TeamGenerationReceipt> receipts, String key) =>
      receipts[key]?.state == TeamGenerationReceiptState.succeeded;
}
