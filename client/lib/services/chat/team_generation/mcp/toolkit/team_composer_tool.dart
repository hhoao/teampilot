import 'team_composer_tool_call.dart';
import 'team_composer_tool_response.dart';

/// Team Composer MCP tool: advertisement (`tools/list`) + handler (`tools/call`).
abstract class TeamComposerTool {
  const TeamComposerTool();

  String get name;
  String get description;
  Map<String, Object?> get inputSchema;

  /// Optional structured result contract for clients/models.
  Map<String, Object?>? get outputSchema => null;

  /// Advisory MCP annotations (not a security boundary).
  Map<String, Object?>? get annotations => null;

  /// When true, the handler serializes the call through
  /// [TeamGenerationWorkflowExecutor] so mutating tools never race.
  bool get serializesMutations => true;

  Future<TeamComposerMcpResult> call(TeamComposerToolCall call);

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    if (outputSchema != null) 'outputSchema': outputSchema,
    if (annotations != null) 'annotations': annotations,
  };
}

/// Convenience base that binds [name] to a tool-name constant.
abstract class NamedTeamComposerTool extends TeamComposerTool {
  const NamedTeamComposerTool(this.toolName);

  final String toolName;

  @override
  String get name => toolName;
}
