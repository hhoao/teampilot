import 'dart:async';

import '../../../models/mcp_server_spec.dart';
import '../../../models/team_config.dart';
import '../../cli/registry/config_profile/config_profile_scope.dart';
import '../contribution/resource_origin.dart';

/// Focused inputs needed by MCP providers.
class McpProviderContext {
  const McpProviderContext({
    required this.cli,
    this.scope,
    this.catalogAccess,
    this.extraServers = const [],
    this.credentials = const {},
    this.layout,
  });

  final CliTool cli;
  final LaunchProfileScope? scope;
  final Object? catalogAccess;
  final List<McpServerSpec> extraServers;
  final Map<String, String> credentials;
  final Object? layout;
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
