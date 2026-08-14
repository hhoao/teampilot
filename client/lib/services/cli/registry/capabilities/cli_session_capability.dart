import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../launch/work_plane_script_runner.dart';
import '../../../storage/runtime_layout.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_registry.dart';
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

/// Context for CLI work after [LaunchManifest] has been flushed to the work
/// plane (local disk or SSH batch).
final class PostManifestFlushContext {
  const PostManifestFlushContext({
    required this.workFs,
    required this.workHome,
    required this.environment,
    this.remoteRunner,
    this.reportDetail,
  });

  /// Work-plane filesystem (local or SFTP).
  final Filesystem workFs;

  /// Real user home on the work plane (`RuntimeContext.home`).
  final String workHome;

  /// Staged launch environment (includes fake `HOME` when applicable).
  final Map<String, String> environment;

  /// Non-null on SSH/Termux work planes — prefer one remote script over SFTP.
  final WorkPlaneScriptRunner? remoteRunner;

  /// Optional progress detail for the provision UI (`cursor-home-passthrough`).
  final void Function(String detail)? reportDetail;
}

/// Tool-specific session persistence, phased initialization, post-flush work,
/// launch argv, and on-disk CONFIG_DIR layout.
abstract interface class CliSessionCapability implements CliCapability {
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

  /// Optional per-CLI work after session trees exist on the work plane.
  /// CLIs without post-flush work fall back to [NoopCliSessionCapability].
  Future<void> afterManifestFlush(PostManifestFlushContext ctx);

  /// CLI argv for the PTY launch of one roster member.
  List<String> buildArguments(CliLaunchContext context);

  /// Resolves the on-disk CONFIG_DIR a CLI reads for a session/member.
  ///
  /// Most CLIs use the standard `sessionRuntimeToolDir` via
  /// [DefaultCliConfigLayout]. A CLI whose layout differs (cursor isolates a
  /// fake `$HOME`) overrides so the knowledge lives in one capability instead
  /// of `if (cli == …)` branches scattered across services.
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  });
}

/// Standard layout: the session tool dir *is* the CONFIG_DIR.
final class DefaultCliConfigLayout implements CliSessionCapability {
  const DefaultCliConfigLayout();

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async =>
      const CliSessionPersistResult();

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async =>
      const CliSessionInitResult();

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) =>
      const CliSessionGateDecision(allowed: true);

  @override
  CliSessionPhase? peekSessionPhase(CliSessionGateContext ctx) => null;

  @override
  Future<void> afterManifestFlush(PostManifestFlushContext ctx) async {}

  @override
  List<String> buildArguments(CliLaunchContext context) => const [];

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => layout.sessionRuntimeToolDir(
    workspaceId,
    sessionId,
    tool.value,
    memberId: memberId,
  );
}

/// Resolves the CONFIG_DIR for [tool] via its [CliSessionCapability],
/// falling back to [DefaultCliConfigLayout] when the CLI registers no session
/// capability.
String sessionConfigDirForTool(
  CliTool tool,
  RuntimeLayout layout, {
  required String workspaceId,
  required String sessionId,
  String? memberId,
  String? teamId,
  CliToolRegistry? registry,
}) {
  final cap =
      (registry ?? CliToolRegistry.builtIn())
          .capability<CliSessionCapability>(tool) ??
      const DefaultCliConfigLayout();
  return cap.sessionConfigDir(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
}
