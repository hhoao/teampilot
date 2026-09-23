/// Launch-facing loopback MCP gateway: session registration, endpoint URLs,
/// and agent-status session tokens.
abstract interface class TeammateBusMcpGatewayPort {
  Future<void> ensureStarted();

  Uri get mcpEndpoint;
  Uri get catalogMcpEndpoint;
  Uri get teamComposerMcpEndpoint;
  Uri get sessionSshMcpEndpoint;
  Uri get idleEndpoint;
  Uri get agentStatusEndpoint;

  int get httpPort;
  int get rawSocketPort;

  bool isSessionRegistered(String sessionId);

  String registerAgentStatusSession({
    required String sessionId,
    String? token,
  });
}
