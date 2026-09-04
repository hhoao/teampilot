import '../team_composer_mcp_constants.dart';
import '../toolkit/team_composer_tool.dart';
import '../toolkit/team_composer_tool_call.dart';
import '../toolkit/team_composer_tool_response.dart';
import '../toolkit/team_composer_tool_schemas.dart';

/// Return the immutable generation context for the active workflow.
final class GetGenerationContextTool extends NamedTeamComposerTool {
  const GetGenerationContextTool() : super(TeamComposerToolName.getContext);

  @override
  bool get serializesMutations => false;

  @override
  String get description =>
      'Return the frozen generation context for this builder workflow: '
      'originalPrompt, requestedMode, ranked modelPool, launch constraints, '
      'and planSchema. Call this first before planning. Do not use Catalog or '
      'filesystem search to rediscover schema. Returns no secrets.';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'description': 'No arguments. Workflow identity comes from the session token.',
    'properties': const <String, Object?>{},
    'additionalProperties': false,
  };

  @override
  Map<String, Object?> get outputSchema => TeamComposerToolSchemas.contextOutput;

  @override
  Map<String, Object?> get annotations =>
      TeamComposerToolSchemas.readOnlyAnnotations;

  @override
  Future<TeamComposerMcpResult> call(TeamComposerToolCall call) async {
    final job = await call.readActiveJob();
    if (job == null) return call.error('workflow_not_active');
    final payload = await call.ctx.contextProvider(job);
    return call.ok(payload);
  }
}
