import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../chat/launch/staging/manifest/work_plane_script_runner.dart';
import '../../../storage/runtime_layout.dart';
import '../../../chat/team_bus/member_bus_idle_endpoint.dart';
import '../cli_capability.dart';
import '../cli_tool_registry.dart';
import '../config_profile/config_profile_context.dart';
import 'workspace_base_info_capability.dart';

/// On-disk hook writer targets for launch-time resource provision.
typedef SessionHookMaterializationPaths = ({
  String hooksDir,
  String? configPath,
});

/// Phased initialization for a CLI session on the work plane.
enum CliSessionPhase { persisted, auth, config, overlay, ready, degraded }

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
    this.additionalDirectories = const [],
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
  final List<String> additionalDirectories;
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
    this.additionalDirectories = const [],
    this.workspaceBaseInfo = WorkspaceBaseInfoPromptInputs.empty,
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
  final List<String> additionalDirectories;
  final WorkspaceBaseInfoPromptInputs workspaceBaseInfo;
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
/// and on-disk CONFIG_DIR layout.
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

  /// Canonical fake `$HOME` root before host-specific preparation (junction).
  ///
  /// Null when this CLI does not isolate resources under a member home tree
  /// (most CLIs use [sessionConfigDir] only).
  String? sessionIsolatedHomeRoot(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  });

  /// Host-specific preparation so resource writers hit the resolved home path
  /// (e.g. Windows junction). Only called when [sessionIsolatedHomeRoot] is
  /// non-null.
  Future<String> prepareSessionIsolatedHome({
    required Filesystem fs,
    required String canonicalHome,
  });

  /// Hook directory + optional sidecar config for [CliResourceProvisioner].
  SessionHookMaterializationPaths hookMaterializationPaths({
    required p.Context pathContext,
    required String memberToolDir,
    String? memberHome,
    TeamMemberConfig? member,
  });
}

/// Standard layout: the session tool dir *is* the CONFIG_DIR.
final class DefaultCliConfigLayout implements CliSessionCapability {
  const DefaultCliConfigLayout();

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async => const CliSessionPersistResult();

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async => const CliSessionInitResult();

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
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }  ) => layout.sessionRuntimeToolDir(
    workspaceId,
    sessionId,
    tool.value,
    memberId: memberId,
  );

  @override
  String? sessionIsolatedHomeRoot(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) =>
      null;

  @override
  Future<String> prepareSessionIsolatedHome({
    required Filesystem fs,
    required String canonicalHome,
  }) async =>
      canonicalHome;

  @override
  SessionHookMaterializationPaths hookMaterializationPaths({
    required p.Context pathContext,
    required String memberToolDir,
    String? memberHome,
    TeamMemberConfig? member,
  }) => (
    hooksDir: pathContext.join(memberToolDir, 'hooks'),
    configPath: null,
  );
}

CliSessionCapability _sessionCapabilityFor(
  CliTool tool, {
  CliToolRegistry? registry,
}) {
  return (registry ?? CliToolRegistry.builtIn()).capability<CliSessionCapability>(
        tool,
      ) ??
      const DefaultCliConfigLayout();
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
  final cap = _sessionCapabilityFor(tool, registry: registry);
  return cap.sessionConfigDir(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
}

/// Isolated member home root for resource/prompt/hook writers, if any.
String? sessionIsolatedHomeRootForTool(
  CliTool tool,
  RuntimeLayout layout, {
  required String workspaceId,
  required String sessionId,
  String? memberId,
  String? teamId,
  CliToolRegistry? registry,
}) {
  final cap = _sessionCapabilityFor(tool, registry: registry);
  return cap.sessionIsolatedHomeRoot(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
}

/// Resolves and prepares isolated member home before Phase-A resource writes.
Future<String?> sessionMemberHomePreparedForResourceWrites({
  required Filesystem fs,
  required CliTool tool,
  required RuntimeLayout layout,
  required String workspaceId,
  required String sessionId,
  String? memberId,
  String? teamId,
  CliToolRegistry? registry,
}) async {
  final cap = _sessionCapabilityFor(tool, registry: registry);
  final root = cap.sessionIsolatedHomeRoot(
    layout,
    tool,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );
  if (root == null || root.trim().isEmpty) return null;
  return cap.prepareSessionIsolatedHome(fs: fs, canonicalHome: root);
}

/// Hook materialization paths for [tool] via [CliSessionCapability].
SessionHookMaterializationPaths hookMaterializationPathsForTool(
  CliTool tool, {
  required p.Context pathContext,
  required String memberToolDir,
  String? memberHome,
  TeamMemberConfig? member,
  CliToolRegistry? registry,
}) {
  final cap = _sessionCapabilityFor(tool, registry: registry);
  return cap.hookMaterializationPaths(
    pathContext: pathContext,
    memberToolDir: memberToolDir,
    memberHome: memberHome,
    member: member,
  );
}
