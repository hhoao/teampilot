/// Constants for the Team Composer MCP server (generation workflow only).
abstract final class TeamComposerMcpConstants {
  /// Loopback HTTP path served beside the catalog MCP route.
  static const mcpPath = '/team-composer/mcp';

  /// Header carrying the ephemeral workflow token; never in argv or env.
  static const tokenHeader = 'X-Team-Generation-Token';

  /// Reuses the gateway's session header so the gateway can build a principal.
  static const sessionHeader = 'X-Session';

  static const serverName = 'team-composer';

  static const protocolVersion = '2025-06-18';
}

/// JSON-RPC error codes specific to the composer route.
abstract final class TeamComposerRpcErrorCode {
  /// Missing/invalid/rotated workflow token (checked before dispatch).
  static const unauthorized = -32001;

  /// Session purpose/workflow/workspace mismatch.
  static const forbidden = -32002;
}

/// The four composer tools exposed to the builder.
abstract final class TeamComposerToolName {
  static const getContext = 'get_generation_context';
  static const probeTargets = 'probe_workspace_targets';
  static const validatePlan = 'validate_team_plan';
  static const finalize = 'finalize_team_generation';

  static const all = [getContext, probeTargets, validatePlan, finalize];
}
