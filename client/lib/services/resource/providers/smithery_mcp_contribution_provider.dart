import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../../mcp/smithery_mcp_auth.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'mcp_contribution_provider.dart';

/// Applies Smithery catalog authentication while preserving source identity.
final class SmitheryMcpContributionProvider
    implements McpContributionProvider, McpContributionProviderDiagnostics {
  SmitheryMcpContributionProvider({required this.source, this.apiToken});

  final McpContributionProvider source;
  final String? apiToken;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  String get providerId => 'smithery-auth';

  @override
  Future<Iterable<McpContribution>> provide(McpProviderContext context) async {
    try {
      final token = apiToken ?? context.credentials['smithery'];
      final provided = await source.provide(context);
      _diagnostics = source is McpContributionProviderDiagnostics
          ? List.unmodifiable(
              (source as McpContributionProviderDiagnostics).diagnostics,
            )
          : const [];
      return [
        for (final contribution in provided)
          McpContribution(
            sourceId: contribution.sourceId,
            server: _apply(contribution.server, token),
            hasCatalogCredentialSource: contribution.hasCatalogCredentialSource,
            origin: ContributionOrigin(
              providerId: contribution.origin.providerId,
              kind: contribution.origin.kind,
              sourceId: contribution.origin.sourceId,
            ),
          ),
      ];
    } on ResourceAssemblyException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw ResourceAssemblyException([
        ResourceAssemblyError.provider(
          resourceKind: ResourceContributionKind.mcp,
          cli: context.cli,
          providerId: source.providerId,
          sourceId: _activeSourceId(context),
          message: 'Smithery MCP provider failed: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      ]);
    }
  }

  String? _activeSourceId(McpProviderContext context) =>
      source is McpContributionProviderSourceMetadata
      ? (source as McpContributionProviderSourceMetadata).activeSourceId
      : context.sourceId;

  McpServerSpec _apply(McpServerSpec server, String? token) {
    if (server is! RemoteMcpServer || token == null || token.trim().isEmpty) {
      return server;
    }
    final headers = Map<String, String>.from(server.headers);
    final raw = <String, Object?>{
      'type': 'http',
      'url': server.url,
      'headers': headers,
    };
    final applied = SmitheryMcpAuth.applyCatalogBearer(raw, token);
    return RemoteMcpServer(
      name: server.name,
      enabled: server.enabled,
      url: server.url,
      headers: (applied['headers'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      bearerTokenEnvVar: server.bearerTokenEnvVar,
    );
  }
}
