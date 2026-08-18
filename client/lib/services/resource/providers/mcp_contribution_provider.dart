import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by MCP providers.
class McpProviderContext {
  McpProviderContext({
    required this.cli,
    this.scope,
    Iterable<McpServerSpec> extraServers = const [],
    Map<String, String> credentials = const {},
  }) : extraServers = List.unmodifiable(extraServers),
       credentials = Map.unmodifiable(credentials);

  final CliTool cli;
  final LaunchProfileScope? scope;
  final List<McpServerSpec> extraServers;
  final Map<String, String> credentials;
}

/// A target-neutral MCP server contribution.
class McpContribution {
  const McpContribution({
    required this.sourceId,
    required this.server,
    required this.origin,
  });

  final String sourceId;
  final McpServerSpec server;
  final ContributionOrigin origin;
}

/// Supplies MCP contributions without writing target configuration.
abstract interface class McpContributionProvider {
  String get providerId;

  FutureOr<Iterable<McpContribution>> provide(McpProviderContext context);
}
