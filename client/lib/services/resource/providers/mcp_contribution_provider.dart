import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../contribution/resource_assembly_error.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by MCP providers.
class McpProviderContext {
  McpProviderContext({
    required this.cli,
    this.scope,
    Iterable<String> mcpServerIds = const [],
    Iterable<McpServerSpec> extraServers = const [],
    Map<String, Map<String, Object?>> extraServerEntries = const {},
    Map<String, String> credentials = const {},
    this.sourceId,
  }) : extraServers = List.unmodifiable(extraServers),
       extraServerEntries = Map.unmodifiable({
         for (final entry in extraServerEntries.entries)
           entry.key: _freezeMap(entry.value),
       }),
       credentials = Map.unmodifiable(credentials),
       mcpServerIds = List.unmodifiable(mcpServerIds);

  final CliTool cli;
  final LaunchProfileScope? scope;
  final List<String> mcpServerIds;
  final List<McpServerSpec> extraServers;
  final Map<String, Map<String, Object?>> extraServerEntries;
  final Map<String, String> credentials;
  final String? sourceId;
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) => Map.unmodifiable(
  {for (final entry in value.entries) entry.key: _freezeValue(entry.value)},
);

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries) entry.key: _freezeValue(entry.value),
    });
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_freezeValue));
  }
  return value;
}

/// A target-neutral MCP server contribution.
class McpContribution {
  const McpContribution({
    required this.sourceId,
    required this.server,
    required this.origin,
    this.hasCatalogCredentialSource = false,
  });

  final String sourceId;
  final McpServerSpec server;
  final ContributionOrigin origin;

  /// Whether this contribution was resolved through a catalog source that
  /// requires the existing app-level credential merge. This is independent
  /// from [origin.kind]: an identity snapshot is a team-layer contribution
  /// but still originates from the MCP catalog.
  final bool hasCatalogCredentialSource;
}

/// Supplies MCP contributions without writing target configuration.
abstract interface class McpContributionProvider {
  String get providerId;

  FutureOr<Iterable<McpContribution>> provide(McpProviderContext context);
}

/// Optional diagnostics emitted while a provider filters or reads its source.
abstract interface class McpContributionProviderDiagnostics {
  List<ResourceAssemblyDiagnostic> get diagnostics;
}

/// Exposes the concrete source currently being read by a provider wrapper.
///
/// This is intentionally separate from [McpContributionProvider.providerId]:
/// a provider can wrap several catalog/source ids and failures must retain the
/// source that was actually being accessed.
abstract interface class McpContributionProviderSourceMetadata {
  String? get activeSourceId;
}
