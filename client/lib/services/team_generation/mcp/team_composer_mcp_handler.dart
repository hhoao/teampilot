import '../../team_bus/mcp/jsonrpc.dart';
import '../../team_bus/mcp/mcp_method.dart';
import 'team_composer_mcp_constants.dart';
import 'toolkit/team_composer_tool.dart';
import 'toolkit/team_composer_tool_call.dart';
import 'toolkit/team_composer_tool_context.dart';
import 'toolkit/team_composer_tool_registry.dart';
import 'toolkit/team_composer_tool_response.dart';

export 'toolkit/team_composer_tool_context.dart'
    show
        ComposerPrincipal,
        PlanValidationOutcome,
        TeamComposerToolContext,
        advanceTeamGenerationPhase;
export 'toolkit/team_composer_tool_response.dart' show TeamComposerMcpResult;

/// Principal resolved by the gateway for one composer request.
typedef TeamComposerPrincipalFactory = Future<ComposerPrincipal?> Function(
  String sessionId,
);

/// Deprecated alias kept for existing call sites / tests.
typedef TeamComposerHandlerContext = TeamComposerToolContext;

/// JSON-RPC tool dispatcher for the Team Composer MCP.
///
/// Authorization happens at the gateway (token + principal); this handler
/// re-checks the durable job before every mutating tool and serializes
/// mutations through the shared [TeamGenerationWorkflowExecutor].
final class TeamComposerMcpHandler {
  TeamComposerMcpHandler({required this.context})
    : _tools = teamComposerToolByName();

  final TeamComposerToolContext context;
  final Map<String, TeamComposerTool> _tools;

  static const protocolVersion = TeamComposerMcpConstants.protocolVersion;
  static const serverName = TeamComposerMcpConstants.serverName;

  /// Tool schemas with `additionalProperties: false` everywhere.
  Map<String, Object?> toolSchemas() => {
    for (final tool in _tools.values) tool.name: tool.inputSchema,
  };

  /// MCP `tools/list` advertisement (name + description + inputSchema).
  List<Map<String, Object?>> advertisedTools() =>
      listAdvertisedTeamComposerTools();

  /// Handshake / discovery methods that must succeed before Cursor will load
  /// the server. Authorization is enforced only on `tools/call`.
  JsonRpcResponse? handleProtocol(JsonRpcRequest req) {
    switch (req.method) {
      case McpMethod.initialize:
        return JsonRpcResponse.result(req.id, {
          'protocolVersion': protocolVersion,
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': serverName, 'version': '1.0.0'},
        });
      case McpMethod.notificationsInitialized:
      case McpMethod.notificationsProgress:
      case McpMethod.notificationsCancelled:
        return null;
      case McpMethod.ping:
        return JsonRpcResponse.result(req.id, const {});
      case McpMethod.toolsList:
        return JsonRpcResponse.result(req.id, {'tools': advertisedTools()});
      default:
        return JsonRpcResponse.error(
          req.id,
          JsonRpcErrorCode.methodNotFound,
          'Method not found: ${req.method}',
        );
    }
  }

  /// Handles one tools/call request for an already-authorized principal.
  Future<TeamComposerMcpResult> handleToolCall({
    required Object? requestId,
    required String toolName,
    required Map<String, Object?> arguments,
    required ComposerPrincipal principal,
  }) async {
    final tool = _tools[toolName];
    if (tool == null) {
      return TeamComposerToolResponse.error(requestId, 'unknown_tool');
    }

    final call = TeamComposerToolCall(
      ctx: context,
      requestId: requestId,
      arguments: arguments,
      principal: principal,
    );

    if (!tool.serializesMutations) {
      return tool.call(call);
    }

    return context.executor.run(
      principal.workspaceId,
      principal.workflowId,
      () => tool.call(call),
    );
  }
}
