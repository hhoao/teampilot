import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../storage/runtime_layout.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../cli_session_manifest.dart';
import '../cli_session_manifest_store.dart';
import 'cursor_session_lifecycle_paths.dart';

/// Cursor mixed-session lifecycle: warm tier, manifest phases, connect gate.
final class CursorSessionLifecycleCapability
    implements CliSessionLifecycleCapability {
  const CursorSessionLifecycleCapability({
    required CliSessionManifestStore manifestStore,
  }) : _manifestStore = manifestStore;

  final CliSessionManifestStore _manifestStore;

  /// Stable overlay generation from bus idle endpoint binding (port/token).
  static int overlayGenerationForBus(MemberBusIdleEndpoint? busIdle) {
    if (busIdle == null) return 0;
    final url = busIdle.url.trim();
    final token = busIdle.token?.trim() ?? '';
    final sessionId = busIdle.sessionId?.trim() ?? '';
    if (url.isEmpty && token.isEmpty && sessionId.isEmpty) return 0;
    return Object.hash(url, token, sessionId) & 0x7fffffff;
  }

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async {
    final paths = _pathsForPersist(ctx);
    final slug = paths.workspaceSlug;
    final overlayGen = overlayGenerationForBus(ctx.busIdle);

    await paths.ensureSharedDirs();

    final memberIds = _resolveMemberIds(ctx);
    for (final memberId in memberIds) {
      await paths.ensureMemberHomeLayout(memberId: memberId);
    }

    final existing = await _manifestStore.read(
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );

    final members = Map<String, CliSessionManifestMember>.from(
      existing?.members ?? const {},
    );
    for (final memberId in memberIds) {
      final prior = members[memberId];
      members[memberId] = CliSessionManifestMember(
        homeRoot: _sessionRelativePath(
          fs: ctx.paths.fs,
          layout: ctx.paths.layout,
          workspaceId: ctx.workspaceId,
          sessionId: ctx.sessionId,
          absolutePath: paths.memberHomeRoot(memberId),
        ),
        overlayGeneration: prior?.overlayGeneration ?? overlayGen,
        chatId: prior?.chatId,
        resumeCapturedAtMs: prior?.resumeCapturedAtMs,
      );
    }

    final shared = CliSessionManifestShared(
      root: _sessionRelativePath(
        fs: ctx.paths.fs,
        layout: ctx.paths.layout,
        workspaceId: ctx.workspaceId,
        sessionId: ctx.sessionId,
        absolutePath: paths.sharedRoot(),
      ),
      projectsDir: _sessionRelativePath(
        fs: ctx.paths.fs,
        layout: ctx.paths.layout,
        workspaceId: ctx.workspaceId,
        sessionId: ctx.sessionId,
        absolutePath: paths.sharedProjectsDir(slug),
      ),
      cliConfigBase: _sessionRelativePath(
        fs: ctx.paths.fs,
        layout: ctx.paths.layout,
        workspaceId: ctx.workspaceId,
        sessionId: ctx.sessionId,
        absolutePath: ctx.paths.fs.pathContext.join(
          paths.sharedRoot(),
          'cli-config.base.json',
        ),
      ),
      authDir: _sessionRelativePath(
        fs: ctx.paths.fs,
        layout: ctx.paths.layout,
        workspaceId: ctx.workspaceId,
        sessionId: ctx.sessionId,
        absolutePath: paths.sharedAuthDir(),
      ),
    );

    final manifest = CliSessionManifest(
      schemaVersion: existing?.schemaVersion ?? 1,
      tool: CursorSessionLifecyclePaths.tool,
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      workspacePathHash: slug,
      workspaceSlug: slug,
      phase: existing?.phase ?? CliSessionPhase.persisted,
      phaseUpdatedAtMs: existing?.phaseUpdatedAtMs,
      shared: shared,
      index: existing?.index ?? const CliSessionManifestIndex(),
      members: members,
    );

    await _manifestStore.write(
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      tool: CursorSessionLifecyclePaths.tool,
      manifest: manifest,
    );

    return const CliSessionPersistResult(phase: CliSessionPhase.persisted);
  }

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async =>
      const CliSessionInitResult();

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) {
    final manifest = _manifestStore.peek(
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) {
      return const CliSessionGateDecision(allowed: false, reason: 'manifest');
    }

    final member = manifest.members[ctx.memberId];
    final expectedOverlay = overlayGenerationForBus(ctx.busIdle);
    if (member != null && member.overlayGeneration != expectedOverlay) {
      return const CliSessionGateDecision(allowed: false, reason: 'overlay');
    }

    switch (manifest.phase) {
      case CliSessionPhase.ready:
        return const CliSessionGateDecision(allowed: true);
      case CliSessionPhase.degraded:
        return const CliSessionGateDecision(allowed: true);
      case CliSessionPhase.indexing:
        final leader = manifest.index.leaderMemberId;
        if (leader != null && leader == ctx.memberId) {
          return const CliSessionGateDecision(allowed: true);
        }
        return const CliSessionGateDecision(
          allowed: false,
          reason: 'indexing',
        );
      default:
        return CliSessionGateDecision(
          allowed: false,
          reason: manifest.phase.name,
        );
    }
  }

  CursorSessionLifecyclePaths _pathsForPersist(CliSessionPersistContext ctx) {
    return CursorSessionLifecyclePaths(
      fs: ctx.paths.fs,
      layout: ctx.paths.layout,
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      workingDirectory: ctx.workingDirectory,
    );
  }

  String _sessionRelativePath({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String workspaceId,
    required String sessionId,
    required String absolutePath,
  }) {
    final sessionDir = layout.workspace.sessionDir(workspaceId, sessionId);
    return fs.pathContext.normalize(
      fs.pathContext.relative(absolutePath, from: sessionDir),
    );
  }

  Iterable<String> _resolveMemberIds(CliSessionPersistContext ctx) {
    final single = ctx.memberId?.trim() ?? '';
    if (single.isNotEmpty) return [single];

    final team = ctx.team;
    if (team == null) return const [];

    return [
      for (final member in team.members)
        if (_memberUsesCursor(member, team)) member.id,
    ];
  }

  bool _memberUsesCursor(TeamMemberConfig member, TeamProfile team) {
    return (member.cli ?? team.cli) == CliTool.cursor;
  }
}
