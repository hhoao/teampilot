import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';
import 'mcp_contribution_provider.dart';

/// Contributes launch-generated MCP servers such as TeamBus endpoints.
final class ExtraMcpContributionProvider
    implements McpContributionProvider, McpContributionProviderDiagnostics {
  ExtraMcpContributionProvider({
    Iterable<McpServerSpec>? extraServers,
    Map<String, Map<String, Object?>>? extraServerEntries,
  }) : _extraServers = extraServers == null
           ? null
           : List.unmodifiable(extraServers),
       _extraServerEntries = extraServerEntries == null
           ? null
           : Map.unmodifiable(extraServerEntries);

  final List<McpServerSpec>? _extraServers;
  final Map<String, Map<String, Object?>>? _extraServerEntries;

  List<ResourceAssemblyDiagnostic> _diagnostics = const [];

  @override
  List<ResourceAssemblyDiagnostic> get diagnostics => _diagnostics;

  @override
  String get providerId => 'extra';

  @override
  FutureOr<Iterable<McpContribution>> provide(McpProviderContext context) {
    final diagnostics = <ResourceAssemblyDiagnostic>[];
    final extraServers = _extraServers ?? context.extraServers;
    final extraServerEntries =
        _extraServerEntries ?? context.extraServerEntries;
    final contributions = <McpContribution>[
      for (final server in extraServers)
        McpContribution(
          sourceId: server.name,
          server: server,
          origin: ContributionOrigin(
            providerId: 'extra',
            kind: ResourceOriginKind.managed,
            sourceId: server.name,
          ),
        ),
    ];
    for (final entry in extraServerEntries.entries) {
      final spec = McpServerSpec.fromCatalogJson(entry.key, entry.value);
      if (spec == null) {
        diagnostics.add(
          ResourceAssemblyDiagnostic(
            severity: ResourceAssemblyDiagnosticSeverity.warning,
            resourceKind: ResourceContributionKind.mcp,
            cli: context.cli,
            providerId: providerId,
            sourceId: entry.key,
            message: 'Invalid extra MCP payload was discarded.',
          ),
        );
        continue;
      }
      contributions.add(
        McpContribution(
          sourceId: entry.key,
          server: spec,
          origin: ContributionOrigin(
            providerId: 'extra',
            kind: ResourceOriginKind.managed,
            sourceId: entry.key,
          ),
        ),
      );
    }
    _diagnostics = List.unmodifiable(diagnostics);
    return List.unmodifiable(contributions);
  }
}
