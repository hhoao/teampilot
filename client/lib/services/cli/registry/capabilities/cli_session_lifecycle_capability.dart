import '../../../../models/team_config.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';

/// Phased initialization for a CLI session on the work plane.
enum CliSessionPhase {
  persisted,
  auth,
  config,
  overlay,
  ready,
  degraded,
}

class CliSessionGateDecision {
  const CliSessionGateDecision({required this.allowed, this.reason});

  final bool allowed;
  final String? reason;
}

class CliSessionPersistContext {
  const CliSessionPersistContext({
    required this.workspaceId,
    required this.sessionId,
    required this.tool,
    required this.paths,
    this.memberId,
    this.team,
    this.busIdle,
    this.workingDirectory = '',
    this.crossMachine = false,
  });

  final String workspaceId;
  final String sessionId;
  final String? memberId;
  final CliTool tool;
  final ConfigProfileDelegate paths;
  final TeamProfile? team;
  final MemberBusIdleEndpoint? busIdle;
  final String workingDirectory;
  final bool crossMachine;
}

class CliSessionInitContext {
  const CliSessionInitContext({
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.tool,
    required this.paths,
    this.team,
    this.busIdle,
    this.workingDirectory = '',
    this.crossMachine = false,
    this.resolvedProviderId,
    this.credentialBasePath,
  });

  final String workspaceId;
  final String sessionId;
  final String memberId;
  final CliTool tool;
  final ConfigProfileDelegate paths;
  final TeamProfile? team;
  final MemberBusIdleEndpoint? busIdle;
  final String workingDirectory;
  final bool crossMachine;

  /// Launch-resolved Cursor provider id (preset / member / team), when known.
  final String? resolvedProviderId;

  /// Control-plane teampilot root for provider credential reads (defaults to
  /// [paths.basePath] when omitted).
  final String? credentialBasePath;
}

class CliSessionGateContext {
  const CliSessionGateContext({
    required this.workspaceId,
    required this.sessionId,
    required this.memberId,
    required this.tool,
    this.paths,
    this.team,
    this.busIdle,
    this.workingDirectory = '',
    this.crossMachine = false,
  });

  final String workspaceId;
  final String sessionId;
  final String memberId;
  final CliTool tool;
  final ConfigProfileDelegate? paths;
  final TeamProfile? team;
  final MemberBusIdleEndpoint? busIdle;
  final String workingDirectory;
  final bool crossMachine;
}

class CliSessionFinalizeContext {
  const CliSessionFinalizeContext({
    required this.workspaceId,
    required this.sessionId,
    required this.tool,
    required this.paths,
    this.memberId,
    this.team,
    this.busIdle,
    this.workingDirectory = '',
    this.crossMachine = false,
  });

  final String workspaceId;
  final String sessionId;
  final String? memberId;
  final CliTool tool;
  final ConfigProfileDelegate paths;
  final TeamProfile? team;
  final MemberBusIdleEndpoint? busIdle;
  final String workingDirectory;
  final bool crossMachine;
}

class CliSessionPersistResult {
  const CliSessionPersistResult({
    this.phase = CliSessionPhase.ready,
    this.warnings = const [],
    this.blocked = false,
  });

  final CliSessionPhase phase;
  final List<String> warnings;
  final bool blocked;
}

class CliSessionInitResult {
  const CliSessionInitResult({
    this.phase = CliSessionPhase.ready,
    this.warnings = const [],
    this.blocked = false,
  });

  final CliSessionPhase phase;
  final List<String> warnings;
  final bool blocked;
}

/// Tool-specific session persistence and phased initialization.
abstract interface class CliSessionLifecycleCapability implements CliCapability {
  /// Create warm tier dirs, symlinks, manifest; idempotent.
  Future<CliSessionPersistResult> ensurePersisted(CliSessionPersistContext ctx);

  /// Run phase machine up to [targetPhase] or until blocked.
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  });

  /// Session/tab close or member dispose: flush manifest, optional checkpoint.
  Future<void> finalize(CliSessionFinalizeContext ctx);

  /// Whether PTY connect is allowed for this member right now.
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx);

  /// Manifest phase when [ctx.paths] is set; null when unknown.
  CliSessionPhase? peekSessionPhase(CliSessionGateContext ctx);
}
