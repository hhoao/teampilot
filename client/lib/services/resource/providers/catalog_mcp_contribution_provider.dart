import 'dart:async';
import 'dart:convert';

import '../../../models/mcp_server.dart';
import '../../../models/mcp_server_spec.dart';
import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import '../../../repositories/mcp_repository.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'mcp_contribution_provider.dart';

/// Resolves enabled catalog ids or a persisted identity snapshot to neutral
/// MCP server contributions.
final class CatalogMcpContributionProvider
    implements McpContributionProvider, McpContributionProviderDiagnostics {
  CatalogMcpContributionProvider({
    this.catalogLoader,
    this.snapshotPath,
    Filesystem? fs,
    this.originKind = ResourceOriginKind.catalog,
  }) : _fs = fs ?? LocalFilesystem();

  final FutureOr<Iterable<McpServer>> Function()? catalogLoader;
  final String? snapshotPath;
  final Filesystem _fs;
  final ResourceOriginKind originKind;
  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  String get providerId => 'catalog';

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  Future<Iterable<McpContribution>> provide(McpProviderContext context) async {
    final snapshot = snapshotPath?.trim() ?? '';
    if (snapshot.isNotEmpty) return _fromSnapshot(context, snapshot);

    final catalog = await (catalogLoader?.call() ?? McpRepository().loadAll());
    final byId = <String, McpServer>{};
    for (final server in catalog) {
      byId.putIfAbsent(server.id, () => server);
    }

    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final seenIds = <String>{};
    final contributions = <McpContribution>[];
    for (final rawId in context.mcpServerIds) {
      final id = rawId.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      final server = byId[id];
      if (server == null) {
        diagnostics.add(
          _warning(
            context.cli,
            id,
            'Unknown MCP catalog id $id was discarded.',
          ),
        );
        continue;
      }
      if (!server.enabled) {
        diagnostics.add(
          _warning(
            context.cli,
            id,
            'Disabled MCP catalog id $id was discarded.',
          ),
        );
        continue;
      }
      final spec = McpServerSpec.fromCatalogJson(
        server.configKey,
        server.server,
      );
      if (spec == null) {
        diagnostics.add(
          _warning(
            context.cli,
            id,
            'Invalid MCP catalog payload for $id was discarded.',
          ),
        );
        continue;
      }
      contributions.add(
        McpContribution(
          sourceId: id,
          server: spec,
          origin: ContributionOrigin(
            providerId: providerId,
            kind: originKind,
            sourceId: id,
          ),
        ),
      );
    }
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }

  Future<Iterable<McpContribution>> _fromSnapshot(
    McpProviderContext context,
    String path,
  ) async {
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final stat = await _fs.stat(path);
    if (!stat.isFile) {
      _diagnostics = const [];
      return const [];
    }
    final text = await _fs.readString(path);
    if (text == null || text.trim().isEmpty) {
      _diagnostics = const [];
      return const [];
    }
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    final rawServers =
        (root['mcpServers'] as Map?)?.cast<String, Object?>() ?? const {};
    final contributions = <McpContribution>[];
    for (final entry in rawServers.entries) {
      final spec = McpServerSpec.fromCatalogJson(
        entry.key,
        entry.value is Map
            ? (entry.value as Map).cast<String, Object?>()
            : const {},
      );
      if (spec == null) {
        diagnostics.add(
          _warning(
            context.cli,
            entry.key,
            'Invalid MCP snapshot payload was discarded.',
          ),
        );
        continue;
      }
      contributions.add(
        McpContribution(
          sourceId: entry.key,
          server: spec,
          origin: ContributionOrigin(
            providerId: providerId,
            kind: originKind,
            sourceId: entry.key,
          ),
        ),
      );
    }
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }

  ResourceAssemblyDiagnostic _warning(
    CliTool cli,
    String sourceId,
    String message,
  ) => ResourceAssemblyDiagnostic(
    severity: ResourceAssemblyDiagnosticSeverity.warning,
    resourceKind: ResourceContributionKind.mcp,
    cli: cli,
    providerId: providerId,
    sourceId: sourceId,
    message: message,
  );
}
