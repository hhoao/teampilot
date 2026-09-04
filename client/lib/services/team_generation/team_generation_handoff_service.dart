import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/agent_runtime/runtime_event.dart';
import '../../utils/team/team_member_naming.dart';
import '../prompt_delivery/prompt_delivery.dart';
import '../prompt_delivery/prompt_delivery_coordinator.dart';
import '../prompt_delivery/prompt_delivery_store.dart';
import 'models/team_generation_job.dart';
import 'team_generation_job_store.dart';
import 'team_generation_session_port.dart';

/// Raised when a tracked delivery is in an ambiguous state (submitIssued /
/// submittedUnknown) without a succeeded workflow receipt. Recovery keeps
/// both sessions and surfaces explicit user resolution — never auto-replay.
final class PromptDeliveryUnknownException implements Exception {
  PromptDeliveryUnknownException(this.deliveryId, this.message);

  final String deliveryId;
  final String message;

  @override
  String toString() => 'PromptDeliveryUnknownException($deliveryId): $message';
}

/// Outcome of one handoff run.
final class TeamGenerationHandoffResult {
  const TeamGenerationHandoffResult({
    required this.destinationSessionId,
    required this.deliveryId,
  });

  final String destinationSessionId;
  final String deliveryId;
}

/// Idempotent destination session selection/open and exact prompt delivery.
///
/// Destination id and delivery ids are reserved from the job before any
/// effect; crashes between receipts recover forward without duplicating
/// sessions or replaying an ambiguous PTY write.
final class TeamGenerationHandoffService {
  TeamGenerationHandoffService({
    required TeamGenerationJobStore jobStore,
    required TeamGenerationSessionPort sessionPort,
    required PromptDeliveryCoordinator promptCoordinator,
    required PromptDeliveryStore promptStore,
  }) : _jobStore = jobStore,
       _sessionPort = sessionPort,
       _promptCoordinator = promptCoordinator,
       _promptStore = promptStore;

  final TeamGenerationJobStore _jobStore;
  final TeamGenerationSessionPort _sessionPort;
  final PromptDeliveryCoordinator _promptCoordinator;
  final PromptDeliveryStore _promptStore;

  Future<TeamGenerationHandoffResult> handoff({
    required Workspace workspace,
    required TeamProfile team,
    required String workflowId,
  }) async {
    final job = await _jobStore.read(workspace.workspaceId, workflowId);
    if (job == null) {
      throw StateError('missing workflow: $workflowId');
    }
    final destination = job.validatedDestination;
    if (destination == null) {
      throw StateError('workflow has no validated destination');
    }

    // Reserve/reuse the deterministic destination id (never regress phase).
    final destinationSessionId = job.destinationSessionId.isNotEmpty
        ? job.destinationSessionId
        : teamGenerationStableId('teamgen-', workflowId);
    final reservedJob = await _jobStore.mutate(
      workspace.workspaceId,
      workflowId,
      (current) => current.copyWith(
        destinationSessionId: destinationSessionId,
        phase: _atLeast(current.phase, TeamGenerationPhase.launching),
      ),
    );

    final existing = await _sessionPort.sessionById(destinationSessionId);
    final openResult = existing == null
        ? await _sessionPort.createDestination(
            workspace: workspace,
            team: team,
            projectFolderPath: destination.projectFolderPath,
            workingDirectoryPath: destination.workingDirectoryPath,
            fixedSessionId: destinationSessionId,
          )
        : await _sessionPort.open(destinationSessionId);
    if (!openResult.opened) {
      throw StateError(
        'destination session did not open: ${openResult.status}',
      );
    }
    await _sessionPort.select(destinationSessionId);
    await _jobStore.mutate(workspace.workspaceId, workflowId, (current) {
      return current.copyWith(
        receipts: {
          ...current.receipts,
          'destination': const TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
          ),
        },
      );
    });

    // Deliver the immutable original prompt to the canonical lead. A failed
    // pre-submit delivery receives a new attempt/id; unresolved submit states
    // are intentionally never replayed.
    var current = reservedJob;
    final deliveryId = _deliveryIdFor(current, workflowId);
    final existingDelivery = await _promptStore.read(deliveryId);
    if (existingDelivery != null &&
        (existingDelivery.state == PromptDeliveryState.submitIssued ||
            existingDelivery.state == PromptDeliveryState.submittedUnknown)) {
      // Ambiguous: never replay automatically.
      final jobNow = await _jobStore.read(workspace.workspaceId, workflowId);
      if (jobNow?.receipts['promptDeliveryDelivered']?.state !=
          TeamGenerationReceiptState.succeeded) {
        await _jobStore.mutate(workspace.workspaceId, workflowId, (current) {
          return current.copyWith(
            error: const TeamGenerationJobError(
              code: 'prompt_delivery_unknown',
            ),
          );
        });
        throw PromptDeliveryUnknownException(
          deliveryId,
          'submit outcome unresolved for $deliveryId',
        );
      }
    }
    if (existingDelivery?.state == PromptDeliveryState.failed) {
      await _reserveNextDeliveryAttempt(workspace.workspaceId, workflowId);
      throw StateError(
        'prompt delivery failed: ${existingDelivery?.failureReason}',
      );
    }
    current = await _jobStore.mutate(workspace.workspaceId, workflowId, (job) {
      return job.copyWith(
        phase: _atLeast(job.phase, TeamGenerationPhase.delivering),
        receipts: {
          ...job.receipts,
          'promptDelivery': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.reserved,
            value: job.receipts['promptDelivery']?.value.isNotEmpty == true
                ? job.receipts['promptDelivery']!.value
                : _deliveryIdForAttempt(job.attempt, workflowId),
          ),
        },
      );
    });
    final effectiveDeliveryId = _deliveryIdFor(current, workflowId);

    await _sessionPort.waitForInputReady(
      destinationSessionId,
      TeamMemberNaming.teamLeadName,
      directToPty: true,
    );

    // The destination conversation must show the same immutable user prompt
    // the lead receives. Re-seeding with the stable delivery id reuses the
    // pending record when this workflow resumes.
    await _sessionPort.persistHistoryPending(
      destinationSessionId,
      TeamMemberNaming.teamLeadName,
      job.originalPrompt,
      deliveryId: effectiveDeliveryId,
    );

    // Reuse the exact existing record when present (idempotent replay);
    // otherwise create with the reserved id.
    final delivery = existingDelivery != null
        ? existingDelivery
        : await _promptCoordinator.submit(
            PromptDeliveryRequest(
              seat: RuntimeSeatKey(
                sessionId: destinationSessionId,
                memberId: TeamMemberNaming.teamLeadName,
              ),
              cli: _leadCli(team),
              text: job.originalPrompt,
              deliveryId: effectiveDeliveryId,
            ),
          );

    if (delivery.state == PromptDeliveryState.failed) {
      // Explicit non-submit: reserve a new attempt next run.
      await _reserveNextDeliveryAttempt(workspace.workspaceId, workflowId);
      throw StateError('prompt delivery failed: ${delivery.failureReason}');
    }

    PromptSubmissionResult? submission;
    if (delivery.state == PromptDeliveryState.created ||
        delivery.state == PromptDeliveryState.waitingForInputSurface ||
        delivery.state == PromptDeliveryState.staged) {
      await _promptCoordinator.stage(delivery.id);
      submission = await _promptCoordinator.issueSubmit(delivery.id);
    }

    final completedDelivery = await _promptStore.read(effectiveDeliveryId);
    if (submission != PromptSubmissionResult.submitted &&
        completedDelivery?.state == PromptDeliveryState.submittedUnknown) {
      await _jobStore.mutate(workspace.workspaceId, workflowId, (job) {
        return job.copyWith(
          error: const TeamGenerationJobError(code: 'prompt_delivery_unknown'),
        );
      });
      throw PromptDeliveryUnknownException(
        effectiveDeliveryId,
        'submit outcome unresolved for $effectiveDeliveryId',
      );
    }
    if (completedDelivery?.state == PromptDeliveryState.failed) {
      await _reserveNextDeliveryAttempt(workspace.workspaceId, workflowId);
      throw StateError(
        'prompt delivery failed: ${completedDelivery?.failureReason}',
      );
    }

    await _jobStore.mutate(workspace.workspaceId, workflowId, (current) {
      return current.copyWith(
        phase: TeamGenerationPhase.delivered,
        receipts: {
          ...current.receipts,
          'promptDeliveryDelivered': const TeamGenerationReceipt(
            state: TeamGenerationReceiptState.succeeded,
          ),
        },
      );
    });

    return TeamGenerationHandoffResult(
      destinationSessionId: destinationSessionId,
      deliveryId: effectiveDeliveryId,
    );
  }

  CliTool _leadCli(TeamProfile team) {
    if (team.teamMode == TeamMode.native) return team.cli;
    return team.cli;
  }

  String _deliveryIdFor(TeamGenerationJob job, String workflowId) {
    final receipt = job.receipts['promptDelivery'];
    if (receipt?.value.isNotEmpty == true) return receipt!.value;
    return _deliveryIdForAttempt(job.attempt, workflowId);
  }

  String _deliveryIdForAttempt(int attempt, String workflowId) =>
      teamGenerationStableId('teamgen-prompt-$attempt-', workflowId);

  Future<TeamGenerationJob> _reserveNextDeliveryAttempt(
    String workspaceId,
    String workflowId,
  ) {
    return _jobStore.mutate(workspaceId, workflowId, (job) {
      final attempt = job.attempt + 1;
      return job.copyWith(
        attempt: attempt,
        receipts: {
          ...job.receipts,
          'promptDelivery': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.reserved,
            value: _deliveryIdForAttempt(attempt, workflowId),
          ),
        },
      );
    });
  }

  /// Forward-only phase guard: [to] wins unless the job already passed it.
  TeamGenerationPhase _atLeast(
    TeamGenerationPhase current,
    TeamGenerationPhase to,
  ) {
    final fromRank = teamGenerationActivePhaseRank(current) ?? -1;
    final toRank = teamGenerationActivePhaseRank(to) ?? -1;
    return toRank >= fromRank ? to : current;
  }
}
