import '../../models/team_generation_job.dart';
import '../../team_generation_job_store.dart';
import '../../team_generation_workflow_executor.dart';

/// Principal resolved by the gateway for one composer request.
final class ComposerPrincipal {
  const ComposerPrincipal({
    required this.sessionId,
    required this.workspaceId,
    required this.workflowId,
  });

  final String sessionId;
  final String workspaceId;
  final String workflowId;
}

/// Pure outcome of one plan validation.
final class PlanValidationOutcome {
  const PlanValidationOutcome({
    required this.valid,
    required this.issues,
    required this.normalizedPlan,
    required this.revision,
    this.destination,
  });

  final bool valid;
  final List<Map<String, Object?>> issues;
  final Map<String, Object?> normalizedPlan;
  final String revision;
  final Map<String, Object?>? destination;
}

/// Shared dependencies for Team Composer MCP tool handlers.
final class TeamComposerToolContext {
  const TeamComposerToolContext({
    required this.jobStore,
    required this.executor,
    required this.contextProvider,
    required this.probeRunner,
    required this.planValidator,
    required this.finalizer,
  });

  final TeamGenerationJobStore jobStore;
  final TeamGenerationWorkflowExecutor executor;

  /// Returns the immutable generation context for a valid job.
  final Future<Map<String, Object?>> Function(TeamGenerationJob job)
  contextProvider;

  /// Runs a target probe and returns the redacted probe snapshot.
  final Future<Map<String, Object?>> Function(TeamGenerationJob job)
  probeRunner;

  /// Validates the supplied plan JSON and returns a structured outcome.
  final Future<PlanValidationOutcome> Function(
    TeamGenerationJob job,
    Map<String, Object?> plan,
  )
  planValidator;

  /// Performs the receipt-driven commit + handoff. Runs after the accepted
  /// finalize response is flushed.
  final Future<void> Function(TeamGenerationJob job, String idempotencyKey)
  finalizer;
}

/// Advances an active phase monotonically (never regresses).
TeamGenerationPhase advanceTeamGenerationPhase(
  TeamGenerationPhase from,
  TeamGenerationPhase to,
) {
  final fromRank = teamGenerationActivePhaseRank(from) ?? -1;
  final toRank = teamGenerationActivePhaseRank(to) ?? -1;
  return toRank >= fromRank ? to : from;
}
