import '../../../models/app_session.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../agent_status/member_agent_status_endpoint.dart';
import '../../catalog/catalog_mcp_transport.dart';
import '../../cli/registry/cli_tool_registry.dart';
import '../../ssh/mcp/session_ssh_mcp_transport.dart';
import '../team_bus/remote/member_bus_mcp_config.dart';
import '../team_generation/mcp/team_composer_mcp_transport.dart';

/// One workflow token shared by the Catalog and Team Composer transports for
/// a single builder connect.
final class TeamGenerationMcpAccess {
  const TeamGenerationMcpAccess({
    required this.catalogToken,
    required this.composerToken,
  });

  final String catalogToken;
  final String composerToken;
}

TeamGenerationMcpAccess? issueTeamGenerationMcpAccess({
  required AppSession session,
  required String? Function(AppSession session)? tokenIssuer,
}) {
  if (session.purpose != SessionPurpose.teamGeneration) return null;
  final token = tokenIssuer?.call(session);
  if (token == null || token.isEmpty) {
    throw StateError('team_generation_token_issue_failed');
  }
  return TeamGenerationMcpAccess(catalogToken: token, composerToken: token);
}

/// Composes the app-owned MCP servers inserted during one runtime launch.
///
/// Catalog is available to every reachable seat. Team Composer is deliberately
/// restricted to the purpose-tagged generation Builder and receives the same
/// ephemeral workflow token that the launch host issued for that Builder.
///
/// [isLocalNative] reports whether the home plane is currently a native local
/// backend (host loopback bridge exe reachability); evaluated per launch so a
/// home-plane swap is honored.
Map<String, Map<String, Object?>> composeRuntimeExtraMcpServers({
  required Map<String, Map<String, Object?>> extra,
  required AppSession session,
  required String memberId,
  required CliTool cli,
  required RuntimeKind launchKind,
  required CliToolRegistry cliRegistry,
  required Uri catalogEndpoint,
  required Uri composerEndpoint,
  required bool isLocalNative,
  required String? Function(AppSession session)? teamGenerationTokenIssuer,
  RemoteBusBinding? mixedRemoteBinding,
  MemberAgentStatusEndpoint? agentStatus,
  Workspace? workspace,
  Uri? sessionSshMcpEndpoint,
}) {
  final remoteBinding = catalogRemoteBindingForRuntime(
    mixedRemoteBinding: mixedRemoteBinding,
    agentStatus: agentStatus,
  );
  final teamGenerationAccess = issueTeamGenerationMcpAccess(
    session: session,
    tokenIssuer: teamGenerationTokenIssuer,
  );
  final servers = extraMcpServersWithCatalog(
    extra: extra,
    isRemoteSeat: usesSshTransport(launchKind),
    remoteBinding: remoteBinding,
    catalogConfig: () => resolveCatalogMcpTransportConfig(
      cliRegistry: cliRegistry,
      catalogEndpoint: catalogEndpoint,
      sessionId: session.sessionId,
      memberId: memberId,
      cli: cli,
      isLocalNative: isLocalNative,
      remoteBinding: remoteBinding,
      teamGenerationToken: teamGenerationAccess?.catalogToken,
    ),
  );
  if (session.purpose == SessionPurpose.teamGeneration) {
    final token = teamGenerationAccess?.composerToken;
    if (token == null || token.isEmpty) {
      throw StateError('team_generation_token_issue_failed');
    }
    servers['team-composer'] = resolveTeamComposerMcpTransportConfig(
      cliRegistry: cliRegistry,
      composerEndpoint: composerEndpoint,
      sessionId: session.sessionId,
      memberId: memberId,
      cli: cli,
      workflowToken: token,
      isLocalNative: isLocalNative,
      remoteBinding: remoteBinding,
    );
  }
  if (workspace != null &&
      sessionSshMcpEndpoint != null &&
      shouldInjectSessionSshMcp(
        workspace: workspace,
        launchKind: launchKind,
        remoteBinding: remoteBinding,
      )) {
    return extraMcpServersWithSessionSsh(
      extra: servers,
      config: resolveSessionSshMcpTransportConfig(
        cliRegistry: cliRegistry,
        sessionSshMcpEndpoint: sessionSshMcpEndpoint,
        sessionId: session.sessionId,
        memberId: memberId,
        cli: cli,
        isLocalNative: isLocalNative,
        remoteBinding: usesSshTransport(launchKind) ? remoteBinding : null,
      ),
    );
  }
  return servers;
}

RemoteBusBinding? catalogRemoteBindingForRuntime({
  required RemoteBusBinding? mixedRemoteBinding,
  required MemberAgentStatusEndpoint? agentStatus,
}) {
  if (mixedRemoteBinding != null) return mixedRemoteBinding;
  if (agentStatus == null || !agentStatus.isRemote) return null;
  final port = agentStatus.port;
  final token = agentStatus.token?.trim() ?? '';
  if (port == null || token.isEmpty) return null;
  return RemoteBusBinding(token: token, idleHttpTunnelPort: port);
}
