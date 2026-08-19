import 'dart:convert';

import '../../../../models/team_config.dart';
import '../../../../utils/logging/logger.dart';
import '../provider/cursor_auth_artifacts.dart';
import '../../../io/filesystem.dart';
import '../provider/cursor_cli_config_policy.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_home_provisioner.dart';
import '../provider/cursor_member_home_passthrough.dart';
import '../provider/cursor_provider_credentials_service.dart';
import '../provider/cursor_provider_settings_resolver.dart';
import '../provider/cursor_session_config_dir.dart';
import '../provider/cursor_workspace_warm_tier.dart';
import '../provider/cursor_workspace_trust_provisioner.dart';
import '../../../storage/runtime_layout.dart';
import '../../../team_bus/member_bus_idle_endpoint.dart';
import '../../registry/config_profile/config_profile_context.dart';
import '../../registry/capabilities/cli_session_capability.dart';
import '../../session_lifecycle/cli_session_manifest.dart';
import '../../session_lifecycle/cli_session_manifest_store.dart';
import 'cli_config_merger.dart';
import 'session_lifecycle_paths.dart';

typedef CursorSessionAuthSync =
    Future<void> Function({
      required String providerId,
      required String memberAuthDir,
    });

typedef CursorSessionProviderResolver =
    Future<String?> Function(CliSessionInitContext ctx);

/// Cursor mixed-session lifecycle: warm tier, manifest phases, connect gate,
/// fake-HOME passthrough after manifest flush and CONFIG_DIR layout.
final class CursorSessionLifecycleCapability implements CliSessionCapability {
  const CursorSessionLifecycleCapability({
    CliSessionManifestStore? manifestStore,
    CursorSessionAuthSync? authSync,
    CursorSessionProviderResolver? resolveProviderId,
    int Function()? clock,
  }) : _manifestStoreOverride = manifestStore,
       _authSync = authSync,
       _resolveProviderId = resolveProviderId,
       _clock = clock;

  final CliSessionManifestStore? _manifestStoreOverride;
  static final Map<String, CliSessionManifestStore> _storesByRoot = {};
  final CursorSessionAuthSync? _authSync;
  final CursorSessionProviderResolver? _resolveProviderId;
  final int Function()? _clock;

  static const progressDetail = 'cursor-home-passthrough';

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => CursorSessionConfigDir.resolve(
    layout,
    workspaceId: workspaceId,
    sessionId: sessionId,
    memberId: memberId,
    teamId: teamId,
  );

  @override
  Future<void> afterManifestFlush(PostManifestFlushContext ctx) async {
    final memberHome = ctx.environment['HOME']?.trim() ?? '';
    final realHome = ctx.workHome.trim();
    if (memberHome.isEmpty || realHome.isEmpty || memberHome == realHome) {
      return;
    }

    ctx.reportDetail?.call(progressDetail);
    final started = DateTime.now();
    final runner = ctx.remoteRunner;

    if (runner != null) {
      final script = CursorMemberHomePassthrough.buildRemoteMirrorScript(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );
      if (script.isEmpty) return;
      appLogger.d(
        '[session-launch] cursor home passthrough via ssh begin '
        'realHome=$realHome',
      );
      await runner.runScript(script, operation: 'Cursor home passthrough');
      appLogger.d(
        '[session-launch] cursor home passthrough via ssh done '
        'ms=${DateTime.now().difference(started).inMilliseconds}',
      );
      return;
    }

    appLogger.d(
      '[session-launch] cursor home passthrough begin realHome=$realHome',
    );
    await CursorMemberHomePassthrough(
      fs: ctx.workFs,
    ).mirror(realHomeRoot: realHome, memberHomeRoot: memberHome);
    appLogger.d(
      '[session-launch] cursor home passthrough done '
      'ms=${DateTime.now().difference(started).inMilliseconds}',
    );
  }

  CliSessionManifestStore _store(ConfigProfileDelegate paths) {
    final override = _manifestStoreOverride;
    if (override != null) return override;
    return _storesByRoot.putIfAbsent(
      paths.basePath,
      () => CliSessionManifestStore(fs: paths.fs, layout: paths.layout),
    );
  }

  CliSessionManifestStore? _storeOrOverride(ConfigProfileDelegate? paths) =>
      paths != null ? _store(paths) : _manifestStoreOverride;

  String? _teamIdOrNull(TeamProfile? team) {
    final id = team?.id.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  String _requireTeamId(TeamProfile? team) {
    final id = _teamIdOrNull(team);
    if (id == null) {
      throw StateError('cursor lifecycle requires team id');
    }
    return id;
  }

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

    await paths.ensureSharedDirs();

    final memberIds = _resolveMemberIds(ctx);
    for (final memberId in memberIds) {
      await paths.ensureMemberHomeLayout(
        memberId: memberId,
        realHomeRoot: ctx.paths.home,
      );
      final agentHome = await paths.resolvedMemberHomeRoot(memberId);
      await _provisionMemberWorkspaceTrust(
        fs: ctx.paths.fs,
        memberHome: agentHome,
        workingDirectory: ctx.workingDirectory,
        additionalDirectories: ctx.additionalDirectories,
      );
    }

    final teamId = _requireTeamId(ctx.team);
    final store = _store(ctx.paths);

    final manifest = await store.merge(
      workspaceId: ctx.workspaceId,
      teamId: teamId,
      tool: CursorSessionLifecyclePaths.tool,
      merge: (existing) {
        final members = Map<String, CliSessionManifestMember>.from(
          existing?.members ?? const {},
        );
        for (final memberId in memberIds) {
          final prior = members[memberId];
          members[memberId] = CliSessionManifestMember(
            homeRoot: _workspaceRelativePath(
              fs: ctx.paths.fs,
              layout: ctx.paths.layout,
              workspaceId: ctx.workspaceId,
              absolutePath: paths.memberHomeRoot(memberId),
            ),
            chatId: prior?.chatId,
            resumeCapturedAtMs: prior?.resumeCapturedAtMs,
          );
        }

        final sharedRootRelative = _workspaceRelativePath(
          fs: ctx.paths.fs,
          layout: ctx.paths.layout,
          workspaceId: ctx.workspaceId,
          absolutePath: paths.sharedRoot(),
        );
        final warmPaths = CursorWorkspaceWarmTier.manifestPaths(
          sharedRootRelative,
        );
        final shared = CliSessionManifestShared(
          root: sharedRootRelative,
          projectsDir: _workspaceRelativePath(
            fs: ctx.paths.fs,
            layout: ctx.paths.layout,
            workspaceId: ctx.workspaceId,
            absolutePath: paths.sharedProjectsDir(slug),
          ),
          cliConfigBase: _workspaceRelativePath(
            fs: ctx.paths.fs,
            layout: ctx.paths.layout,
            workspaceId: ctx.workspaceId,
            absolutePath: ctx.paths.fs.pathContext.join(
              paths.sharedRoot(),
              'cli-config.base.json',
            ),
          ),
          pluginsLocalDir: warmPaths.pluginsLocalDir,
          skillsCursorDir: warmPaths.skillsCursorDir,
          mcpBase: warmPaths.mcpBase,
          settingsJson: warmPaths.settingsJson,
        );

        return CliSessionManifest(
          tool: CursorSessionLifecyclePaths.tool,
          workspaceId: ctx.workspaceId,
          teamId: teamId,
          workspacePathHash: slug,
          workspaceSlug: slug,
          phase: existing?.phase ?? CliSessionPhase.persisted,
          phaseUpdatedAtMs: existing?.phaseUpdatedAtMs,
          shared: shared,
          members: members,
          sessionOverlays: existing?.sessionOverlays ?? const {},
        );
      },
    );

    return CliSessionPersistResult(phase: manifest.phase);
  }

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async {
    final warnings = <String>[];

    final teamId = _requireTeamId(ctx.team);
    final store = _store(ctx.paths);
    var manifest = await store.read(
      workspaceId: ctx.workspaceId,
      teamId: teamId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) {
      await ensurePersisted(
        CliSessionPersistContext(
          workspaceId: ctx.workspaceId,
          sessionId: ctx.sessionId,
          memberId: ctx.memberId,
          tool: ctx.tool,
          paths: ctx.paths,
          team: ctx.team,
          busIdle: ctx.busIdle,
          workingDirectory: ctx.workingDirectory,
          additionalDirectories: ctx.additionalDirectories,
          crossMachine: ctx.crossMachine,
        ),
      );
      manifest = await store.read(
        workspaceId: ctx.workspaceId,
        teamId: teamId,
        tool: CursorSessionLifecyclePaths.tool,
      );
      if (manifest == null) {
        return const CliSessionInitResult(
          phase: CliSessionPhase.persisted,
          blocked: true,
          warnings: ['manifest_missing'],
        );
      }
    }

    if (manifest.phase == CliSessionPhase.ready ||
        manifest.phase == CliSessionPhase.degraded) {
      final paths = _pathsForInit(ctx);
      final memberHome = await paths.resolvedMemberHomeRoot(ctx.memberId);
      await _syncMemberAuth(ctx: ctx, paths: paths, memberHome: memberHome);
      if (!await _memberAuthReady(ctx, memberHome)) {
        return CliSessionInitResult(
          phase: manifest.phase,
          warnings: warnings,
          blocked: true,
        );
      }
      final expectedOverlay = overlayGenerationForBus(ctx.busIdle);
      final sessionOverlay = manifest.overlayFor(ctx.sessionId, ctx.memberId);
      if (manifest.members[ctx.memberId] != null &&
          sessionOverlay?.overlayGeneration == expectedOverlay) {
        await _provisionMemberWorkspaceTrust(
          fs: ctx.paths.fs,
          memberHome: memberHome,
          workingDirectory: ctx.workingDirectory,
          additionalDirectories: ctx.additionalDirectories,
        );
        return CliSessionInitResult(phase: manifest.phase, warnings: warnings);
      }
      final homeLayout = CursorHomeLayout(
        pathContext: ctx.paths.fs.pathContext,
      );
      manifest = await _runOverlayPhase(
        ctx,
        paths,
        homeLayout,
        manifest,
        memberHome,
      );
      if (manifest.phase != CliSessionPhase.degraded) {
        manifest = await _writeManifest(
          ctx.paths,
          manifest.copyWith(
            phase: CliSessionPhase.ready,
            phaseUpdatedAtMs: _now(),
          ),
        );
      }
      return CliSessionInitResult(phase: manifest.phase, warnings: warnings);
    }

    final paths = _pathsForInit(ctx);
    final memberHome = await paths.resolvedMemberHomeRoot(ctx.memberId);
    final homeLayout = CursorHomeLayout(pathContext: ctx.paths.fs.pathContext);

    manifest = await _runAuthPhase(ctx, paths, manifest, memberHome);
    manifest = await _runConfigPhase(ctx, paths, homeLayout, manifest);
    manifest = await _runOverlayPhase(
      ctx,
      paths,
      homeLayout,
      manifest,
      memberHome,
    );

    if (manifest.phase != CliSessionPhase.degraded) {
      manifest = await _writeManifest(
        ctx.paths,
        manifest.copyWith(
          phase: CliSessionPhase.ready,
          phaseUpdatedAtMs: _now(),
        ),
      );
    }
    return CliSessionInitResult(phase: manifest.phase, warnings: warnings);
  }

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {
    final memberId = ctx.memberId?.trim() ?? '';
    if (memberId.isEmpty) return;

    final teamId = _teamIdOrNull(ctx.team);
    if (memberId.isEmpty || teamId == null) return;

    final store = _store(ctx.paths);
    final manifest = await store.read(
      workspaceId: ctx.workspaceId,
      teamId: teamId,
      tool: CursorSessionLifecyclePaths.tool,
    );
    if (manifest == null) return;

    final paths = CursorSessionLifecyclePaths(
      fs: ctx.paths.fs,
      layout: ctx.paths.layout,
      workspaceId: ctx.workspaceId,
      teamId: teamId,
      workingDirectory: ctx.workingDirectory,
    );
    final chatId = await _scanLatestChatId(
      fs: ctx.paths.fs,
      memberHome: await paths.resolvedMemberHomeRoot(memberId),
    );
    if (chatId == null) return;

    final members = Map<String, CliSessionManifestMember>.from(
      manifest.members,
    );
    final existing = members[memberId];
    if (existing == null) return;

    members[memberId] = CliSessionManifestMember(
      homeRoot: existing.homeRoot,
      chatId: chatId,
      resumeCapturedAtMs: _now(),
    );
    await _writeManifest(ctx.paths, manifest.copyWith(members: members));
  }

  @override
  CliSessionPhase? peekSessionPhase(CliSessionGateContext ctx) {
    final manifest = _peekManifest(ctx);
    return manifest?.phase;
  }

  CliSessionManifest? _peekManifest(CliSessionGateContext ctx) {
    final teamId = _teamIdOrNull(ctx.team);
    if (teamId == null) return null;
    final store = ctx.paths != null
        ? _store(ctx.paths!)
        : _manifestStoreOverride;
    return store?.peek(
      workspaceId: ctx.workspaceId,
      teamId: teamId,
      tool: CursorSessionLifecyclePaths.tool,
    );
  }

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) {
    final teamId = _teamIdOrNull(ctx.team);
    final store = ctx.paths != null
        ? _store(ctx.paths!)
        : _manifestStoreOverride;
    final manifest = teamId == null
        ? null
        : store?.peek(
            workspaceId: ctx.workspaceId,
            teamId: teamId,
            tool: CursorSessionLifecyclePaths.tool,
          );
    if (manifest == null) {
      return const CliSessionGateDecision(allowed: false, reason: 'manifest');
    }

    final member = manifest.members[ctx.memberId];
    final expectedOverlay = overlayGenerationForBus(ctx.busIdle);
    final sessionOverlay = manifest.overlayFor(ctx.sessionId, ctx.memberId);
    if (member != null && ctx.busIdle != null) {
      if (sessionOverlay == null ||
          sessionOverlay.overlayGeneration != expectedOverlay) {
        return const CliSessionGateDecision(allowed: false, reason: 'overlay');
      }
    }

    switch (manifest.phase) {
      case CliSessionPhase.ready:
      case CliSessionPhase.degraded:
        return const CliSessionGateDecision(allowed: true);
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
      await _syncMemberAuth(ctx: ctx, paths: paths, memberHome: memberHome);
      return manifest;
    }

    await _syncMemberAuth(ctx: ctx, paths: paths, memberHome: memberHome);
    if (!await _memberAuthReady(ctx, memberHome)) {
      return manifest;
    }
    return _writeManifest(
      ctx.paths,
      manifest.copyWith(phase: CliSessionPhase.auth, phaseUpdatedAtMs: _now()),
    );
  }

  Future<bool> _memberAuthReady(
    CliSessionInitContext ctx,
    String memberHome,
  ) async {
    final authFile = _pathsForInit(ctx).memberAuthFile(memberHome);
    final content = await ctx.paths.fs.readString(authFile);
    return content != null &&
        CursorAuthArtifacts.authJsonIndicatesLoggedIn(content);
  }

  Future<void> _syncMemberAuth({
    required CliSessionInitContext ctx,
    required CursorSessionLifecyclePaths paths,
    required String memberHome,
  }) async {
    await paths.ensureMemberAuthDir(memberHome: memberHome);
    final memberAuthDir = paths.memberAuthDir(memberHome);
    final authFile = paths.memberAuthFile(memberHome);
    final providerId = await _providerIdFor(ctx);
    if (providerId != null) {
      if (!(await ctx.paths.fs.stat(authFile)).isFile) {
        await _syncSessionAuth(
          ctx: ctx,
          providerId: providerId,
          memberAuthDir: memberAuthDir,
        );
      }
      final credentials = CursorProviderCredentialsService(
        fs: _credentialFs(ctx),
        basePath: _credentialBasePath(ctx),
      );
      await credentials.syncAuthToMemberHome(providerId, memberHome);
      return;
    }

    await _syncGlobalAuthToMember(
      ctx: ctx,
      paths: paths,
      memberHome: memberHome,
      authFile: authFile,
    );
  }

  Future<void> _syncGlobalAuthToMember({
    required CliSessionInitContext ctx,
    required CursorSessionLifecyclePaths paths,
    required String memberHome,
    required String authFile,
  }) async {
    final layout = CursorHomeLayout(pathContext: ctx.paths.fs.pathContext);
    final home = ctx.paths.home.trim();
    if (home.isEmpty) return;

    for (final candidate in layout.globalAuthJsonCandidates(home)) {
      final content = await _credentialFs(ctx).readString(candidate);
      if (content == null ||
          !CursorAuthArtifacts.authJsonIndicatesLoggedIn(content)) {
        continue;
      }
      await paths.ensureMemberAuthDir(memberHome: memberHome);
      await ctx.paths.fs.atomicWrite(authFile, content);
      return;
    }
  }

  String _credentialBasePath(CliSessionInitContext ctx) {
    final override = ctx.credentialBasePath?.trim() ?? '';
    return override.isNotEmpty ? override : ctx.paths.basePath;
  }

  Filesystem _credentialFs(CliSessionInitContext ctx) {
    final credentialRoot = _credentialBasePath(ctx);
    if (credentialRoot == ctx.paths.basePath) return ctx.paths.fs;
    // Provider store lives on the control plane; read through the same fs when
    // roots match (native). Callers pass credentialBasePath only when needed.
    return ctx.paths.fs;
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

    final basePath = _absoluteWorkspacePath(ctx, manifest.shared.cliConfigBase);
    await ctx.paths.fs.atomicWrite(
      basePath,
      const JsonEncoder.withIndent('  ').convert(warm),
    );

    return _writeManifest(
      ctx.paths,
      manifest.copyWith(
        phase: CliSessionPhase.config,
        phaseUpdatedAtMs: _now(),
      ),
    );
  }

  Future<CliSessionManifest> _runOverlayPhase(
    CliSessionInitContext ctx,
    CursorSessionLifecyclePaths paths,
    CursorHomeLayout homeLayout,
    CliSessionManifest manifest,
    String memberHome,
  ) async {
    final expectedOverlay = overlayGenerationForBus(ctx.busIdle);
    final sessionOverlay = manifest.overlayFor(ctx.sessionId, ctx.memberId);
    final overlayStale =
        sessionOverlay != null &&
        sessionOverlay.overlayGeneration != expectedOverlay;
    final overlayMissing = sessionOverlay == null;
    if (_phaseAtLeast(manifest.phase, CliSessionPhase.overlay) &&
        !overlayStale &&
        !overlayMissing) {
      return manifest;
    }

    final team = ctx.team;
    final member = _memberFor(ctx);
    if (team != null && member != null && member.isValid) {
      final basePath = _absoluteWorkspacePath(
        ctx,
        manifest.shared.cliConfigBase,
      );
      final baseJson = await ctx.paths.fs.readString(basePath);
      final mcpBasePath = _absoluteWorkspacePath(ctx, manifest.shared.mcpBase);
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
        sharedMcpBasePath: mcpBasePath,
      );
    }

    await _provisionMemberWorkspaceTrust(
      fs: ctx.paths.fs,
      memberHome: memberHome,
      workingDirectory: ctx.workingDirectory,
      additionalDirectories: ctx.additionalDirectories,
    );

    final members = Map<String, CliSessionManifestMember>.from(
      manifest.members,
    );
    final sessionOverlays =
        Map<String, Map<String, CliSessionManifestSessionOverlay>>.from(
          manifest.sessionOverlays,
        );
    final memberOverlays = Map<String, CliSessionManifestSessionOverlay>.from(
      sessionOverlays[ctx.sessionId] ?? const {},
    );
    memberOverlays[ctx.memberId] = CliSessionManifestSessionOverlay(
      overlayGeneration: expectedOverlay,
    );
    sessionOverlays[ctx.sessionId] = memberOverlays;

    final keepReadyPhase =
        manifest.phase == CliSessionPhase.ready ||
        manifest.phase == CliSessionPhase.degraded;

    return _writeManifest(
      ctx.paths,
      manifest.copyWith(
        phase: keepReadyPhase ? manifest.phase : CliSessionPhase.overlay,
        phaseUpdatedAtMs: _now(),
        members: members,
        sessionOverlays: sessionOverlays,
      ),
    );
  }

  Future<void> _syncSessionAuth({
    required CliSessionInitContext ctx,
    required String providerId,
    required String memberAuthDir,
  }) async {
    final authSync = _authSync;
    if (authSync != null) {
      await authSync(providerId: providerId, memberAuthDir: memberAuthDir);
      return;
    }

    final credentials = CursorProviderCredentialsService(
      fs: _credentialFs(ctx),
      basePath: _credentialBasePath(ctx),
    );
    final layout = CursorHomeLayout(pathContext: ctx.paths.fs.pathContext);
    final providerHome = credentials.providerHome(providerId);
    final srcAuth = layout.authJson(providerHome);
    final destAuth = ctx.paths.fs.pathContext.join(
      memberAuthDir,
      CursorHomeLayout.authFileName,
    );
    if ((await ctx.paths.fs.stat(srcAuth)).isFile) {
      await ctx.paths.fs.ensureDir(memberAuthDir);
      await ctx.paths.fs.copyFile(srcAuth, destAuth);
    }
  }

  Future<String?> _providerIdFor(CliSessionInitContext ctx) async {
    final resolver = _resolveProviderId;
    if (resolver != null) return resolver(ctx);

    final credentialBase = _credentialBasePath(ctx);
    final settings = CursorProviderSettingsResolver(basePath: credentialBase);

    final fromLaunch = ctx.resolvedProviderId?.trim() ?? '';
    if (fromLaunch.isNotEmpty) {
      final provider = await settings.findById(fromLaunch);
      if (provider != null) return fromLaunch;
    }

    final team = ctx.team;
    if (team == null) return null;
    return settings.resolveProviderId(team, member: _memberFor(ctx));
  }

  TeamMemberConfig? _memberFor(CliSessionInitContext ctx) {
    final team = ctx.team;
    if (team == null) return null;
    for (final member in team.members) {
      if (member.id == ctx.memberId) return member;
    }
    return null;
  }

  Future<CliSessionManifest> _writeManifest(
    ConfigProfileDelegate? paths,
    CliSessionManifest manifest,
  ) async {
    final store = _storeOrOverride(paths);
    if (store == null) return manifest;
    await store.write(
      workspaceId: manifest.workspaceId,
      teamId: manifest.teamId,
      tool: manifest.tool,
      manifest: manifest,
    );
    return manifest;
  }

  Future<String?> _scanLatestChatId({
    required Filesystem fs,
    required String memberHome,
  }) async {
    final path = fs.pathContext;
    final chatsRoot = path.join(
      CursorHomeLayout(pathContext: path).cursorDir(memberHome),
      'chats',
    );
    String? best;
    var bestUpdated = -1;
    try {
      for (final wsHash in await fs.listDir(chatsRoot)) {
        if (!wsHash.isDirectory) continue;
        final wsDir = path.join(chatsRoot, wsHash.name);
        for (final chat in await fs.listDir(wsDir)) {
          if (!chat.isDirectory) continue;
          final metaRaw = await fs.readString(
            path.join(wsDir, chat.name, 'meta.json'),
          );
          if (metaRaw == null || metaRaw.isEmpty) continue;
          final meta = _decodeJson(metaRaw);
          if (meta == null || meta['hasConversation'] != true) continue;
          final updated = (meta['updatedAtMs'] as num?)?.toInt() ?? 0;
          if (updated > bestUpdated) {
            bestUpdated = updated;
            best = chat.name;
          }
        }
      }
    } on Object {
      return null;
    }
    return best;
  }

  Map<String, Object?>? _decodeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  String _absoluteWorkspacePath(
    CliSessionInitContext ctx,
    String relativePath,
  ) {
    final workspaceDir = ctx.paths.layout.workspace.workspaceDir(
      ctx.workspaceId,
    );
    return ctx.paths.fs.pathContext.normalize(
      ctx.paths.fs.pathContext.join(workspaceDir, relativePath),
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
    CliSessionPhase.ready => 4,
    CliSessionPhase.degraded => 4,
  };

  int _now() => _clock?.call() ?? DateTime.now().millisecondsSinceEpoch;

  CursorSessionLifecyclePaths _pathsForPersist(CliSessionPersistContext ctx) {
    return CursorSessionLifecyclePaths(
      fs: ctx.paths.fs,
      layout: ctx.paths.layout,
      workspaceId: ctx.workspaceId,
      teamId: _requireTeamId(ctx.team),
      workingDirectory: ctx.workingDirectory,
    );
  }

  CursorSessionLifecyclePaths _pathsForInit(CliSessionInitContext ctx) {
    return CursorSessionLifecyclePaths(
      fs: ctx.paths.fs,
      layout: ctx.paths.layout,
      workspaceId: ctx.workspaceId,
      teamId: _requireTeamId(ctx.team),
      workingDirectory: ctx.workingDirectory,
    );
  }

  String _workspaceRelativePath({
    required Filesystem fs,
    required RuntimeLayout layout,
    required String workspaceId,
    required String absolutePath,
  }) {
    final workspaceDir = layout.workspace.workspaceDir(workspaceId);
    return fs.pathContext.normalize(
      fs.pathContext.relative(absolutePath, from: workspaceDir),
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

  Future<void> _provisionMemberWorkspaceTrust({
    required Filesystem fs,
    required String memberHome,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
  }) async {
    final home = memberHome.trim();
    final workDir = workingDirectory.trim();
    if (home.isEmpty || workDir.isEmpty) return;
    await CursorWorkspaceTrustProvisioner(fs: fs).provisionLaunchWorkspaces(
      homeRoot: home,
      workingDirectory: workDir,
      additionalDirectories: additionalDirectories,
    );
  }
}
