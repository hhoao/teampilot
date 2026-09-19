import '../../models/team_generation_job.dart';
import '../team_composer_mcp_constants.dart';
import '../toolkit/team_composer_tool.dart';
import '../toolkit/team_composer_tool_call.dart';
import '../toolkit/team_composer_tool_context.dart';
import '../toolkit/team_composer_tool_response.dart';
import '../toolkit/team_composer_tool_schemas.dart';

/// Probe workspace machine targets for the active workflow.
final class ProbeWorkspaceTargetsTool extends NamedTeamComposerTool {
  const ProbeWorkspaceTargetsTool() : super(TeamComposerToolName.probeTargets);

  @override
  String get description =>
      'Probe workspace machine targets and persist a redacted availability '
      'snapshot for placement. Call after designing roles and before assigning '
      'member placement targetIds. A successful probe clears any prior '
      'validatedRevision — re-validate the plan afterward. Not a substitute '
      'for get_generation_context.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'refresh': {
        'type': 'boolean',
        'description':
            'When true, force a fresh probe even if a snapshot already exists. '
            'When omitted/false, the server may reuse or refresh as needed.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Map<String, Object?> get outputSchema => TeamComposerToolSchemas.probeOutput;

  @override
  Map<String, Object?> get annotations =>
      TeamComposerToolSchemas.mutatingProbeAnnotations;

  @override
  Future<TeamComposerMcpResult> call(TeamComposerToolCall call) async {
    final job = await call.readActiveJob();
    if (job == null) return call.error('workflow_not_active');

    final snapshot = await call.ctx.probeRunner(job);
    final advanced = await call.ctx.jobStore.mutate(
      job.workspaceId,
      job.workflowId,
      (current) => current.copyWith(
        phase: advanceTeamGenerationPhase(
          current.phase,
          TeamGenerationPhase.planning,
        ),
        probeSnapshotJson: snapshot,
        // New probe facts invalidate a previously validated plan.
        validatedRevision: '',
        validatedDestinationJson: null,
      ),
    );
    return call.ok({
      'status': 'probed',
      'phase': advanced.phase.value,
    });
  }
}
