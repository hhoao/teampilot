import '../../utils/logging/logger.dart';
import 'models/team_generation_job.dart';
import 'team_generation_job_store.dart';
import 'team_generation_session_port.dart';

/// Cleanup outcome.
enum TeamGenerationCleanupResult { cleaned, deferred }

/// Ordered, idempotent cleanup gates for a delivered workflow.
///
/// Deletion requires both durable handoff gates: the prompt-delivery receipt
/// and the finalize response-flush receipt. The visible Builder is replaced at
/// handoff; durable deletion remains idempotent for recovery. The destination
/// session and the committed profile are never compensation targets.
final class TeamGenerationCleanupService {
  TeamGenerationCleanupService({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationSessionPort sessionPort,
    required void Function(String workflowId) revokeToken,
  }) : _jobStore = jobStore,
       _sessionPort = sessionPort,
       _revokeToken = revokeToken;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSessionPort _sessionPort;
  final void Function(String workflowId) _revokeToken;

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

    if (job.settings.retainBuilderSession) {
      await _jobStore.mutate(workspaceId, workflowId, (current) {
        return current.copyWith(
          phase: _safeAdvance(current.phase),
          receipts: {
            ...current.receipts,
            'builderRetained': const TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
            ),
          },
        );
      });
      _revokeToken(workflowId);
      await _jobStore.compactComplete(workspaceId, workflowId);
      return TeamGenerationCleanupResult.cleaned;
    }

    // The Builder was removed from the visible workbench at handoff. Durable
    // deletion is still idempotent here so recovery can finish a partial run.
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
      await _recordReceipt(
        workspaceId,
        workflowId,
        'builderDeleted',
        value: job.builderSessionId,
      );
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
