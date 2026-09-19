import '../../models/team_generation_job.dart';
import '../team_composer_mcp_constants.dart';
import '../toolkit/team_composer_tool.dart';
import '../toolkit/team_composer_tool_call.dart';
import '../toolkit/team_composer_tool_context.dart';
import '../toolkit/team_composer_tool_response.dart';
import '../toolkit/team_composer_tool_schemas.dart';

/// Validate a team plan and return a revision receipt.
final class ValidateTeamPlanTool extends NamedTeamComposerTool {
  const ValidateTeamPlanTool() : super(TeamComposerToolName.validatePlan);

  @override
  String get description =>
      'Validate one complete team plan against frozen settings, probes, and '
      'planSchema. Use only after drafting the full plan from '
      'get_generation_context — never as field-by-field schema discovery. '
      'On valid=true, pass revision as validationRevision to '
      'finalize_team_generation. Fix all returned issues in one revision; '
      'prefer ≤3 validate rounds.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'required': ['plan'],
    'additionalProperties': false,
    'properties': {
      'plan': TeamComposerToolSchemas.planProperty,
    },
  };

  @override
  Map<String, Object?> get outputSchema => TeamComposerToolSchemas.validateOutput;

  @override
  Map<String, Object?> get annotations =>
      TeamComposerToolSchemas.validateAnnotations;

  @override
  Future<TeamComposerMcpResult> call(TeamComposerToolCall call) async {
    final job = await call.readActiveJob();
    if (job == null) return call.error('workflow_not_active');

    final plan = call.argObject('plan');
    if (plan == null) return call.error('invalid_plan');

    final outcome = await call.ctx.planValidator(job, plan);
    if (!outcome.valid) {
      await call.ctx.jobStore.mutate(job.workspaceId, job.workflowId, (
        current,
      ) {
        return current.copyWith(
          normalizedPlanJson: outcome.normalizedPlan,
          planRevision: outcome.revision,
          validatedRevision: '',
          validatedDestinationJson: null,
        );
      });
      return call.ok({
        'valid': false,
        'issues': outcome.issues,
        'revision': outcome.revision,
      });
    }

    final updated = await call.ctx.jobStore.mutate(
      job.workspaceId,
      job.workflowId,
      (current) => current.copyWith(
        phase: advanceTeamGenerationPhase(
          current.phase,
          TeamGenerationPhase.validating,
        ),
        normalizedPlanJson: outcome.normalizedPlan,
        planRevision: outcome.revision,
        validatedRevision: outcome.revision,
        validatedDestinationJson: outcome.destination,
      ),
    );
    return call.ok({
      'valid': true,
      'issues': outcome.issues,
      'revision': updated.validatedRevision,
    });
  }
}
