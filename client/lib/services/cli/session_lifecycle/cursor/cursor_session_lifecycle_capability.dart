import 'dart:convert';

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../provider/cursor/cursor_cli_config_policy.dart';
import '../../../provider/cursor/cursor_home_layout.dart';
import '../../../provider/cursor/cursor_home_provisioner.dart';
import '../../../provider/cursor/cursor_provider_credentials_service.dart';
import '../../../provider/cursor/cursor_provider_settings_resolver.dart';
import '../../../storage/runtime_layout.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../cli_session_manifest.dart';
import '../cli_session_manifest_store.dart';
import 'cursor_cli_config_merger.dart';
import 'cursor_session_lifecycle_paths.dart';

typedef CursorSessionAuthSync =
    Future<void> Function({
      required String providerId,
      required String sharedAuthDir,
    });

typedef CursorSessionProviderResolver =
    Future<String?> Function(CliSessionInitContext ctx);

/// Cursor mixed-session lifecycle: warm tier, manifest phases, connect gate.
final class CursorSessionLifecycleCapability
    implements CliSessionLifecycleCapability {
  CursorSessionLifecycleCapability({
    required CliSessionManifestStore manifestStore,
    CursorSessionAuthSync? authSync,
    CursorSessionProviderResolver? resolveProviderId,
    int Function()? clock,
  }) : _manifestStore = manifestStore,
       _authSync = authSync,
       _resolveProviderId = resolveProviderId,
       _clock = clock;

  final CliSessionManifestStore _manifestStore;
  final CursorSessionAuthSync? _authSync;
  final CursorSessionProviderResolver? _resolveProviderId;
  final int Function()? _clock;

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
  }) async {
    final warnings = <String>[];

    var manifest = await _manifestStore.read(
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) {
      return const CliSessionInitResult(
        phase: CliSessionPhase.persisted,
        blocked: true,
        warnings: ['manifest_missing'],
      );
    }

    if (manifest.phase == CliSessionPhase.ready ||
        manifest.phase == CliSessionPhase.degraded) {
      return CliSessionInitResult(phase: manifest.phase, warnings: warnings);
    }

    final paths = _pathsForInit(ctx);
    final memberHome = paths.memberHomeRoot(ctx.memberId);
    final homeLayout = CursorHomeLayout(pathContext: ctx.paths.fs.pathContext);

    manifest = await _runAuthPhase(ctx, paths, manifest, memberHome);
    manifest = await _runConfigPhase(ctx, paths, homeLayout, manifest);
    manifest = await _runOverlayPhase(ctx, paths, homeLayout, manifest, memberHome);

    if (!_phaseAtLeast(manifest.phase, CliSessionPhase.resume)) {
      manifest = await _writeManifest(
        manifest.copyWith(
          phase: CliSessionPhase.resume,
          phaseUpdatedAtMs: _now(),
        ),
      );
    }

    if (await _indexFastPathReady(ctx, paths, manifest)) {
      manifest = await _writeManifest(
        manifest.copyWith(
          phase: CliSessionPhase.ready,
          phaseUpdatedAtMs: _now(),
        ),
      );
      return CliSessionInitResult(phase: CliSessionPhase.ready, warnings: warnings);
    }

    manifest = await _ensureIndexingPhase(ctx, manifest);
    return CliSessionInitResult(
      phase: manifest.phase,
      warnings: warnings,
      blocked:
          manifest.phase == CliSessionPhase.indexing &&
          manifest.index.leaderMemberId != ctx.memberId,
    );
  }

  /// Marks shared index complete and allows non-leader members to connect.
  Future<void> markIndexDone({
    required String workspaceId,
    required String sessionId,
  }) async {
    final manifest = await _manifestStore.read(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) return;

    final now = _now();
    await _writeManifest(
      manifest.copyWith(
        phase: CliSessionPhase.ready,
        phaseUpdatedAtMs: now,
        index: CliSessionManifestIndex(
          leaderMemberId: manifest.index.leaderMemberId,
          startedAtMs: manifest.index.startedAtMs ?? now,
          finishedAtMs: now,
          lastError: null,
        ),
      ),
    );
  }

  /// Marks shared index failed while still allowing degraded connect.
  Future<void> markIndexFailed({
    required String workspaceId,
    required String sessionId,
    String? error,
  }) async {
    final manifest = await _manifestStore.read(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) return;

    final now = _now();
    await _writeManifest(
      manifest.copyWith(
        phase: CliSessionPhase.degraded,
        phaseUpdatedAtMs: now,
        index: CliSessionManifestIndex(
          leaderMemberId: manifest.index.leaderMemberId,
          startedAtMs: manifest.index.startedAtMs ?? now,
          finishedAtMs: manifest.index.finishedAtMs,
          lastError: error ?? 'index_failed',
        ),
      ),
    );
  }

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

  Future<CliSessionManifest> _runAuthPhase(
    CliSessionInitContext ctx,
    CursorSessionLifecyclePaths paths,
    CliSessionManifest manifest,
    String memberHome,
  ) async {
    if (_phaseAtLeast(manifest.phase, CliSessionPhase.auth)) {
      await paths.linkOrCopyAuth(memberHome: memberHome);
      return manifest;
    }

    final sharedAuthDir = paths.sharedAuthDir();
    final authFile = ctx.paths.fs.pathContext.join(
      sharedAuthDir,
      CursorHomeLayout.authFileName,
    );
    if (!(await ctx.paths.fs.stat(authFile)).isFile) {
      final providerId = await _providerIdFor(ctx);
      if (providerId != null) {
        await _syncSessionAuth(
          ctx: ctx,
          providerId: providerId,
          sharedAuthDir: sharedAuthDir,
        );
      }
    }

    await paths.linkOrCopyAuth(memberHome: memberHome);
    return _writeManifest(
      manifest.copyWith(phase: CliSessionPhase.auth, phaseUpdatedAtMs: _now()),
    );
  }

  Future<CliSessionManifest> _runConfigPhase(
    CliSessionInitContext ctx,
    CursorSessionLifecyclePaths paths,
    CursorHomeLayout homeLayout,
    CliSessionManifest manifest,
  ) async {
    if (_phaseAtLeast(manifest.phase, CliSessionPhase.config)) {
      return manifest;
    }

    final userCliConfigPath = homeLayout.cliConfig(ctx.paths.home);
    final raw = await ctx.paths.fs.readString(userCliConfigPath);
    final userConfig = raw != null
        ? (CursorCliConfigPolicy.parseConfigJson(raw) ?? <String, Object?>{})
        : <String, Object?>{};
    final warm = CursorCliConfigMerger.extractWarmTier(userConfig);

    final basePath = _absoluteSessionPath(ctx, manifest.shared.cliConfigBase);
    await ctx.paths.fs.atomicWrite(
      basePath,
      const JsonEncoder.withIndent('  ').convert(warm),
    );

    return _writeManifest(
      manifest.copyWith(phase: CliSessionPhase.config, phaseUpdatedAtMs: _now()),
    );
  }

  Future<CliSessionManifest> _runOverlayPhase(
    CliSessionInitContext ctx,
    CursorSessionLifecyclePaths paths,
    CursorHomeLayout homeLayout,
    CliSessionManifest manifest,
    String memberHome,
  ) async {
    if (_phaseAtLeast(manifest.phase, CliSessionPhase.overlay)) {
      return manifest;
    }

    final team = ctx.team;
    final member = _memberFor(ctx);
    if (team != null && member != null && member.isValid) {
      final basePath = _absoluteSessionPath(ctx, manifest.shared.cliConfigBase);
      final baseJson = await ctx.paths.fs.readString(basePath);
      final credentials = CursorProviderCredentialsService(
        fs: ctx.paths.fs,
        basePath: ctx.paths.basePath,
      );
      await CursorHomeProvisioner(
        fs: ctx.paths.fs,
        credentials: credentials,
        layout: homeLayout,
      ).provisionOverlayOnly(
        memberHome: memberHome,
        member: member,
        busIdle: ctx.busIdle,
        forceTeamLeadDelegateMode: team.forceTeamLeadDelegateMode,
        cliConfigJson: baseJson,
      );
    }

    final members = Map<String, CliSessionManifestMember>.from(manifest.members);
    final existing = members[ctx.memberId];
    if (existing != null) {
      members[ctx.memberId] = CliSessionManifestMember(
        homeRoot: existing.homeRoot,
        overlayGeneration: overlayGenerationForBus(ctx.busIdle),
        chatId: existing.chatId,
        resumeCapturedAtMs: existing.resumeCapturedAtMs,
      );
    }

    return _writeManifest(
      manifest.copyWith(
        phase: CliSessionPhase.overlay,
        phaseUpdatedAtMs: _now(),
        members: members,
      ),
    );
  }

  Future<CliSessionManifest> _ensureIndexingPhase(
    CliSessionInitContext ctx,
    CliSessionManifest manifest,
  ) async {
    if (manifest.phase == CliSessionPhase.indexing &&
        manifest.index.leaderMemberId != null) {
      return manifest;
    }

    final now = _now();
    final leaderId =
        manifest.index.leaderMemberId ?? _firstCursorMemberId(ctx) ?? ctx.memberId;

    return _writeManifest(
      manifest.copyWith(
        phase: CliSessionPhase.indexing,
        phaseUpdatedAtMs: now,
        index: CliSessionManifestIndex(
          leaderMemberId: leaderId,
          startedAtMs: manifest.index.startedAtMs ?? now,
          finishedAtMs: manifest.index.finishedAtMs,
          lastError: manifest.index.lastError,
        ),
      ),
    );
  }

  Future<void> _syncSessionAuth({
    required CliSessionInitContext ctx,
    required String providerId,
    required String sharedAuthDir,
  }) async {
    final authSync = _authSync;
    if (authSync != null) {
      await authSync(providerId: providerId, sharedAuthDir: sharedAuthDir);
      return;
    }

    final credentials = CursorProviderCredentialsService(
      fs: ctx.paths.fs,
      basePath: ctx.paths.basePath,
    );
    final layout = CursorHomeLayout(pathContext: ctx.paths.fs.pathContext);
    final providerHome = credentials.providerHome(providerId);
    final srcAuth = layout.authJson(providerHome);
    final destAuth = ctx.paths.fs.pathContext.join(
      sharedAuthDir,
      CursorHomeLayout.authFileName,
    );
    if ((await ctx.paths.fs.stat(srcAuth)).isFile) {
      await ctx.paths.fs.ensureDir(sharedAuthDir);
      await ctx.paths.fs.copyFile(srcAuth, destAuth);
    }
  }

  Future<String?> _providerIdFor(CliSessionInitContext ctx) async {
    final resolver = _resolveProviderId;
    if (resolver != null) return resolver(ctx);

    final team = ctx.team;
    if (team == null) return null;
    return CursorProviderSettingsResolver(
      basePath: ctx.paths.basePath,
    ).resolveProviderId(team, member: _memberFor(ctx));
  }

  Future<bool> _indexFastPathReady(
    CliSessionInitContext ctx,
    CursorSessionLifecyclePaths paths,
    CliSessionManifest manifest,
  ) async {
    if (manifest.index.finishedAtMs == null) return false;
    final entries = await ctx.paths.fs.listDir(paths.sharedProjectsDir());
    return entries.isNotEmpty;
  }

  TeamMemberConfig? _memberFor(CliSessionInitContext ctx) {
    final team = ctx.team;
    if (team == null) return null;
    for (final member in team.members) {
      if (member.id == ctx.memberId) return member;
    }
    return null;
  }

  String? _firstCursorMemberId(CliSessionInitContext ctx) {
    final team = ctx.team;
    if (team == null) return null;
    for (final member in team.members) {
      if (_memberUsesCursor(member, team)) return member.id;
    }
    return null;
  }

  Future<CliSessionManifest> _writeManifest(CliSessionManifest manifest) async {
    await _manifestStore.write(
      workspaceId: manifest.workspaceId,
      sessionId: manifest.sessionId,
      tool: manifest.tool,
      manifest: manifest,
    );
    return manifest;
  }

  String _absoluteSessionPath(CliSessionInitContext ctx, String relativePath) {
    final sessionDir = ctx.paths.layout.workspace.sessionDir(
      ctx.workspaceId,
      ctx.sessionId,
    );
    return ctx.paths.fs.pathContext.normalize(
      ctx.paths.fs.pathContext.join(sessionDir, relativePath),
    );
  }

  bool _phaseAtLeast(CliSessionPhase current, CliSessionPhase target) {
    return _phaseRank(current) >= _phaseRank(target);
  }

  int _phaseRank(CliSessionPhase phase) => switch (phase) {
    CliSessionPhase.persisted => 0,
    CliSessionPhase.auth => 1,
    CliSessionPhase.config => 2,
    CliSessionPhase.overlay => 3,
    CliSessionPhase.resume => 4,
    CliSessionPhase.indexing => 5,
    CliSessionPhase.ready => 6,
    CliSessionPhase.degraded => 6,
  };

  int _now() => _clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  CursorSessionLifecyclePaths _pathsForPersist(CliSessionPersistContext ctx) {
    return CursorSessionLifecyclePaths(
      fs: ctx.paths.fs,
      layout: ctx.paths.layout,
      workspaceId: ctx.workspaceId,
      sessionId: ctx.sessionId,
      workingDirectory: ctx.workingDirectory,
    );
  }

  CursorSessionLifecyclePaths _pathsForInit(CliSessionInitContext ctx) {
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
