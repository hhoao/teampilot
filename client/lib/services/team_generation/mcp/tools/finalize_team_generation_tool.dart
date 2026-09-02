import '../../../../utils/logging/logger.dart';
import '../../models/team_generation_job.dart';
import '../team_composer_mcp_constants.dart';
import '../toolkit/team_composer_tool.dart';
import '../toolkit/team_composer_tool_call.dart';
import '../toolkit/team_composer_tool_context.dart';
import '../toolkit/team_composer_tool_response.dart';
import '../toolkit/team_composer_tool_schemas.dart';

/// Commit a validated team plan and hand off generation.
final class FinalizeTeamGenerationTool extends NamedTeamComposerTool {
  const FinalizeTeamGenerationTool() : super(TeamComposerToolName.finalize);

  @override
  String get description =>
      'Accept a previously validated plan and hand off to TeamPilot commit + '
      'destination launch. Call exactly once after validate_team_plan returns '
      'valid=true. Pass the same plan, its validationRevision, and one stable '
      'idempotencyKey. Replaying the same key is safe; a different key after '
      'commit is rejected. After accepted=true, stop — do not implement the '
      'original task.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['plan', 'validationRevision', 'idempotencyKey'],
    'additionalProperties': false,
    'properties': {
      'plan': TeamComposerToolSchemas.planProperty,
      'validationRevision': {
        'type': 'string',
        'minLength': 1,
        'description':
            'Exact revision string from the last successful validate_team_plan '
            'response. Mismatch returns stale_validation_revision.',
      },
      'idempotencyKey': {
        'type': 'string',
        'minLength': 1,
        'maxLength': 128,
        'pattern': r'^[A-Za-z0-9._:-]+$',
        'description':
            'Caller-chosen key for this finalize attempt, e.g. '
            '"finalize-1". Same key replays the accepted receipt.',
      },
    },
  };

  @override
  Map<String, Object?> get outputSchema => TeamComposerToolSchemas.finalizeOutput;

  @override
  Map<String, Object?> get annotations =>
      TeamComposerToolSchemas.finalizeAnnotations;

  @override
  Future<TeamComposerMcpResult> call(TeamComposerToolCall call) async {
    final job = await call.readActiveJob();
    if (job == null) return call.error('workflow_not_active');

    final plan = call.argObject('plan');
    final revision = call.argString('validationRevision');
    final key = call.argString('idempotencyKey');
    if (plan == null) return call.error('invalid_plan');
    if (key.isEmpty ||
        key.length > 128 ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(key)) {
      return call.error('invalid_idempotency_key');
    }

    final current = await call.ctx.jobStore.read(
      job.workspaceId,
      job.workflowId,
    );
    if (current == null || !current.isActive) {
      return call.error('workflow_not_active');
    }

    // Idempotent replay with the same accepted key.
    final acceptedKey = current.finalizeIdempotencyKey;
    final profileSucceeded =
        current.receipts['profile']?.state ==
        TeamGenerationReceiptState.succeeded;
    if (acceptedKey.isNotEmpty) {
      if (acceptedKey == key) {
        return call.ok({
          'accepted': true,
          'workflowId': current.workflowId,
          'phase': current.phase.value,
        });
      }
      // A different key after profile persistence is immutable.
      if (profileSucceeded) {
        return call.error('immutable_commit');
      }
    }

    if (current.validatedRevision.isEmpty ||
        current.validatedRevision != revision) {
      return call.error('stale_validation_revision');
    }

    // Reserve + record acceptance before responding.
    var updated = await call.ctx.jobStore.mutate(
      current.workspaceId,
      current.workflowId,
      (running) => running.copyWith(
        phase: advanceTeamGenerationPhase(
          running.phase,
          TeamGenerationPhase.committing,
        ),
        finalizeIdempotencyKey: key,
      ),
    );
    updated = await call.ctx.jobStore.mutate(
      updated.workspaceId,
      updated.workflowId,
      (running) {
        return running.copyWith(
          receipts: {
            ...running.receipts,
            'finalizeAccepted': TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
              value: revision,
              updatedAt: running.updatedAt,
            ),
          },
        );
      },
    );

    // The commit/handoff chain runs only after the response is flushed.
    return call.okThenFlush(
      {
        'accepted': true,
        'workflowId': updated.workflowId,
        'phase': updated.phase.value,
      },
      () async {
        try {
          await call.ctx.finalizer(updated, key);
        } on Object catch (e, st) {
          appLogger.e(
            '[team-composer] post-flush finalize failed: $e\n$st',
          );
        }
      },
    );
  }
}
