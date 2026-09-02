import 'dart:convert';

import '../io/filesystem.dart';
import '../../models/app_session.dart';
import '../team_bus/mcp/jsonrpc.dart';
import '../team_bus/mcp/mcp_method.dart';
import '../team_bus/mcp/toolkit/mcp_tool_response.dart';
import '../plugin/plugin_exceptions.dart';
import '../skill/skill_install_service.dart';
import 'catalog_kind.dart';
import 'catalog_kind_registry.dart';
import 'catalog_mcp_constants.dart';

class CatalogMcpSession {
  const CatalogMcpSession({
    required this.sessionId,
    required this.workspaceId,
    this.memberId,
    required this.workFs,
    required this.allowedRoots,
    this.purpose = SessionPurpose.normal,
    this.workflowId = '',
  });

  final String sessionId;
  final String workspaceId;
  final String? memberId;
  final Filesystem workFs;
  final List<String> allowedRoots;

  /// Persisted session role; builders may stage into generation scope only.
  final SessionPurpose purpose;

  /// Builder workflow id (empty for normal sessions).
  final String workflowId;
}

/// JSON-RPC handler for the teampilot catalog MCP server. Pure logic; no HTTP.
class CatalogMcpHandler {
  CatalogMcpHandler({
    required CatalogKindRegistry registry,
    CatalogGenerationMutationHandler? generationMutationHandler,
  }) : _registry = registry,
       _generationMutationHandler = generationMutationHandler;

  final CatalogKindRegistry _registry;
  CatalogGenerationMutationHandler? _generationMutationHandler;

  void attachGenerationMutationHandler(
    CatalogGenerationMutationHandler handler,
  ) {
    _generationMutationHandler = handler;
  }

  static const protocolVersion = '2025-06-18';
  static const serverName = catalogMcpServerName;

  Future<JsonRpcResponse?> handle(
    JsonRpcRequest req,
    CatalogMcpSession session,
  ) async {
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
        return JsonRpcResponse.result(req.id, {
          'tools': [
            for (final tool in _registry.allTools())
              {
                'name': tool.name,
                'description': tool.description,
                'inputSchema': tool.inputSchema,
              },
          ],
        });
      case McpMethod.toolsCall:
        return _callTool(req, session);
      default:
        return JsonRpcResponse.error(
          req.id,
          JsonRpcErrorCode.methodNotFound,
          'Method not found: ${req.method}',
        );
    }
  }

  Future<JsonRpcResponse> _callTool(
    JsonRpcRequest req,
    CatalogMcpSession session,
  ) async {
    final name = req.params[McpParams.toolName];
    if (name is! String || name.isEmpty) {
      return McpToolResponse.invalidParams(req.id, 'Missing tool name');
    }
    try {
      final arguments = req.toolArguments;
      final bindTo = _parseBindTo(arguments['bind_to']);
      final request = CatalogRequest(
        sessionId: session.sessionId,
        workspaceId: session.workspaceId,
        memberId: session.memberId,
        bindTo: bindTo,
        overwrite: arguments['overwrite'] == true,
        arguments: arguments,
        workFs: session.workFs,
        allowedRoots: session.allowedRoots,
        purpose: session.purpose,
        workflowId: session.workflowId,
      );
      final route = _registry.routeFor(name);
      final result = bindTo == CatalogBindTo.generation
          ? await _dispatchGeneration(route, request)
          : await _registry.dispatch(name, request);
      return McpToolResponse.ok(req.id, jsonEncode(_resultToJson(result)));
    } on CatalogException catch (e) {
      return McpToolResponse.toolError(req.id, 'code=${e.code} ${e.message}');
    } on SkillInstallException catch (e) {
      return McpToolResponse.toolError(req.id, _unknownErrorText(e));
    } on PluginException catch (e) {
      return McpToolResponse.toolError(req.id, _unknownErrorText(e));
    } catch (e) {
      return McpToolResponse.toolError(req.id, _unknownErrorText(e));
    }
  }

  static CatalogBindTo _parseBindTo(Object? raw) {
    if (raw == null) return CatalogBindTo.workspace;
    if (raw is String && raw == CatalogBindTo.workspace.name) {
      return CatalogBindTo.workspace;
    }
    if (raw is String && raw == CatalogBindTo.generation.name) {
      return CatalogBindTo.generation;
    }
    throw CatalogException(
      'bind_scope_unsupported',
      'bind_to other than workspace is not supported',
    );
  }

  Future<CatalogResult> _dispatchGeneration(
    ({String kind, CatalogOp op})? route,
    CatalogRequest request,
  ) async {
    if (request.purpose != SessionPurpose.teamGeneration ||
        request.workflowId.isEmpty) {
      throw CatalogException(
        'bind_scope_unsupported',
        'generation scope is only available to Team Builder sessions',
      );
    }
    if (route == null ||
        const {
          CatalogOp.search,
          CatalogOp.list,
          CatalogOp.read,
        }.contains(route.op)) {
      throw CatalogException(
        'bind_scope_unsupported',
        'generation scope accepts catalog mutations only',
      );
    }
    final handler = _generationMutationHandler;
    if (handler == null) {
      throw CatalogException(
        'generation_staging_unsupported',
        'generation staging is unavailable',
      );
    }
    return handler.handleMcpMutation(
      kind: route.kind,
      op: route.op,
      request: request,
    );
  }

  static String _unknownErrorText(Object e) {
    final text = e is SkillInstallException
        ? e.message
        : e is PluginException
        ? e.message
        : '$e';
    final already = text.toLowerCase().contains('already exists');
    return 'code=${already ? 'already_exists' : 'install_failed'} $text';
  }

  static Map<String, Object?> _resultToJson(CatalogResult result) {
    return {
      'ok': result.ok,
      'kind': result.kind,
      'ids': result.ids,
      'workspace_id': result.workspaceId,
      'restart_required': result.restartRequired,
      if (result.boundTo != null) 'bound_to': result.boundTo!.name,
      if (result.message != null) 'message': result.message,
      if (result.data != null) 'data': result.data,
      if (result.failed != null)
        'failed': [
          for (final f in result.failed!)
            {'path': f.path, 'code': f.code, 'message': f.message},
        ],
    };
  }
}
