import '../../models/team_generation_job.dart';
import 'team_composer_tool_context.dart';
import 'team_composer_tool_response.dart';

/// One `tools/call` invocation passed to a [TeamComposerTool] handler.
final class TeamComposerToolCall {
  const TeamComposerToolCall({
    required this.ctx,
    required this.requestId,
    required this.arguments,
    required this.principal,
  });

  final TeamComposerToolContext ctx;
  final Object? requestId;
  final Map<String, Object?> arguments;
  final ComposerPrincipal principal;

  TeamComposerMcpResult ok(Map<String, Object?> data) =>
      TeamComposerToolResponse.ok(requestId, data);

  TeamComposerMcpResult error(String code) =>
      TeamComposerToolResponse.error(requestId, code);

  TeamComposerMcpResult okThenFlush(
    Map<String, Object?> data,
    Future<void> Function() afterResponseFlushed,
  ) => TeamComposerToolResponse.ok(
    requestId,
    data,
    afterResponseFlushed: afterResponseFlushed,
  );

  Future<TeamGenerationJob?> readActiveJob() async {
    final job = await ctx.jobStore.read(
      principal.workspaceId,
      principal.workflowId,
    );
    if (job == null || !job.isActive) return null;
    return job;
  }

  Map<String, Object?>? argObject(String key) {
    final value = arguments[key];
    if (value is! Map) return null;
    return value.cast<String, Object?>();
  }

  String argString(String key) => (arguments[key] as String?)?.trim() ?? '';
}
