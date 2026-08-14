import 'package:path/path.dart' as p;

import '../../models/plugin.dart';
import '../../models/team_config.dart';
import '../../utils/lock_pool.dart';
import '../../utils/logging/logger.dart';
import '../cli/registry/capabilities/marketplace_consumer_capability.dart';
import '../cli/registry/capabilities/plugin_manifest_paths.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../storage/workspace_layout.dart';
import 'cli_plugin_layout.dart';
import 'cli_plugin_provision_cache.dart';
import 'plugin_repo_disk_cache_service.dart';
import 'plugin_repo_service.dart';

/// Tools whose plugin provisioning consumes marketplaces from the session
/// CONFIG_DIR (`{config}/plugins/marketplaces`).
Iterable<CliTool> get marketplaceConsumerTools => CliToolRegistry.builtIn()
    .withCapability<MarketplaceConsumerCapability>()
    .where((def) => CliToolRegistry.builtIn()
        .capability<MarketplaceConsumerCapability>(def.id)
        ?.consumesMarketplaces == true)
    .map((def) => def.id);

/// Single owner of **shared** marketplace materialization.
///
/// Every CLI session gets its own isolated CONFIG_DIR; without sharing, each
/// session ends up with a full copy of every marketplace. This store collapses
/// that to one shared artifact per (tool × marketplace):
///
///   git cache    `plugins/marketplace-cache/{owner}/{name}@{branch}`   — one raw clone, managed by git sync
///   flavor dir   `plugins/marketplace-flavors/{tool}/{owner}/{name}@{branch}` — per-tool copy + flavor projection, written once
///   session link `{CONFIG_DIR}/plugins/marketplaces/{name}`            — symlink → flavor dir
///
/// Sessions only ever reference a **flavor dir**, never the raw git cache, so
/// tool writes (e.g. a CLI re-syncing its marketplace) can never pollute the
/// shared git clone. Symlinks fall back to a copy when the backend lacks
/// symlink support.
class MarketplaceSharedStore {
  MarketplaceSharedStore({required this.fs, required this.teampilotRoot});

  final Filesystem fs;
  final String teampilotRoot;

  static final LockPool _locks = LockPool();

  p.Context get _ctx => fs.pathContext;

  /// Cache root for [teampilotRoot], e.g. `{root}/plugins/marketplace-cache`.
  String get cacheRoot =>
      AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(teampilotRoot);

  /// Root holding per-tool materialized marketplaces.
  String get flavorRoot =>
      _ctx.join(teampilotRoot, 'plugins', 'marketplace-flavors');

  // ---- Path resolution (single source of truth) ---------------------------

  String cacheDirFor(PluginMarketplace m) => _ctx.join(
    cacheRoot,
    m.owner.trim(),
    '${m.name.trim()}@${m.branch.trim()}',
  );

  String flavorDirFor(CliTool tool, PluginMarketplace m) => _ctx.join(
    flavorRoot,
    tool.value,
    m.owner.trim(),
    '${m.name.trim()}@${m.branch.trim()}',
  );

  static String _flavorLockKey(CliTool tool, PluginMarketplace m) =>
      '${tool.value}|${m.owner}/${m.name}@${m.branch}';

  static String _linkLockKey(String dest) => 'link|$dest';

  // ---- Cache ---------------------------------------------------------------

  /// Ensures the shared git cache clone exists (clone-once, coalesced).
  ///
  /// Returns the cache dir, or `null` when git/network is unavailable and no
  /// cached checkout exists — callers then fall back to the CLI cloning
  /// per-session (the pre-existing behavior, no regression).
  Future<String?> ensureCache(
    PluginMarketplace m, {
    PluginRepoDiskCacheService? diskCache,
  }) async {
    final cacheDir = cacheDirFor(m);
    if ((await fs.stat(cacheDir)).isDirectory) return cacheDir;
    final service =
        diskCache ??
        PluginRepoDiskCacheService(
          filesystem: fs,
          teampilotRoot: teampilotRoot,
        );
    try {
      return await service.syncMarketplace(m);
    } on Object catch (e, st) {
      appLogger.w(
        '[MarketplaceSharedStore] cache sync failed for ${m.fullName}: $e',
      );
      appLogger.d(st.toString());
      return null;
    }
  }

  // ---- Per-tool shared flavor dir ------------------------------------------

  /// Materializes the per-tool flavor dir once (cache → flavor + flavor
  /// projection + stamp). Returns the flavor dir, or `null` when no cache is
  /// available.
  Future<String?> ensureShared({
    required CliTool tool,
    required PluginMarketplace marketplace,
    required PluginManifestPaths paths,
  }) async {
    final cacheDir = cacheDirFor(marketplace);
    if (!(await fs.stat(cacheDir)).isDirectory) return null;
    final flavorDir = flavorDirFor(tool, marketplace);

    return _locks.synchronized(
      _flavorLockKey(tool, marketplace),
      () => _ensureSharedUnlocked(
        flavorDir: flavorDir,
        cacheDir: cacheDir,
        paths: paths,
      ),
    );
  }

  Future<String> _ensureSharedUnlocked({
    required String flavorDir,
    required String cacheDir,
    required PluginManifestPaths paths,
  }) async {
    if (await CliPluginProvisionCache.isMarketplaceMaterializationCurrent(
      fs: fs,
      dest: flavorDir,
      teampilotCacheDir: cacheDir,
    )) {
      return flavorDir;
    }

    await fs.ensureDir(_ctx.dirname(flavorDir));
    if ((await fs.lstat(flavorDir)).exists) {
      await fs.removeRecursive(flavorDir);
    }
    await fs.copyTree(source: cacheDir, destination: flavorDir);
    await CliPluginLayout.projectBundleToFlavor(fs, flavorDir, paths);
    await CliPluginProvisionCache.writeMarketplaceSourceStamp(
      fs: fs,
      dest: flavorDir,
      teampilotCacheDir: cacheDir,
    );
    appLogger.d(
      '[MarketplaceSharedStore] materialized ${_ctx.basename(flavorDir)} → $flavorDir',
    );
    return flavorDir;
  }

  // ---- Session linking -----------------------------------------------------

  /// Symlinks `{configDir}/plugins/marketplaces/{name}` → the shared flavor
  /// dir. Idempotent: a correct link is kept; a real directory (an in-flight
  /// CLI clone or a TeamPilot materialization) is left to the sweep.
  Future<String?> ensureSessionLinked({
    required String configDir,
    required CliTool tool,
    required PluginMarketplace marketplace,
    required PluginManifestPaths paths,
  }) async {
    final shared = await ensureShared(tool: tool, marketplace: marketplace, paths: paths);
    if (shared == null) return null;
    final dest = _ctx.join(
      configDir,
      'plugins',
      'marketplaces',
      marketplace.name.trim(),
    );
    await _locks.synchronized(
      _linkLockKey(dest),
      () => _ensureSessionLinkedUnlocked(dest: dest, shared: shared),
    );
    return shared;
  }

  Future<void> _ensureSessionLinkedUnlocked({
    required String dest,
    required String shared,
  }) async {
    final destStat = await fs.lstat(dest);
    if (destStat.isSymlink) {
      final target = await fs.readSymlinkTarget(dest);
      if (target != null &&
          _ctx.normalize(_ctx.absolute(target)) ==
              _ctx.normalize(_ctx.absolute(shared))) {
        return;
      }
      // Stale link: createSymlink below removes and re-links it.
    } else if (destStat.exists && destStat.isDirectory) {
      return;
    }
    await fs.ensureDir(_ctx.dirname(dest));
    final linked = await fs.createSymlink(target: shared, linkPath: dest);
    if (!linked) {
      await fs.copyTree(source: shared, destination: dest);
    }
  }

  /// Ensures every known marketplace is shared into [configDir] for [tool].
  /// Best-effort: a failing marketplace is logged and skipped.
  Future<void> ensureSessionMarketplacesLinked({
    required String configDir,
    required CliTool tool,
  }) async {
    final paths = pluginManifestPathsForTool(tool);
    if (paths == null) return;
    final markets = await PluginRepoService.loadMarketplacesFor(fs, teampilotRoot);
    for (final m in markets) {
      try {
        await ensureSessionLinked(
          configDir: configDir,
          tool: tool,
          marketplace: m,
          paths: paths,
        );
      } on Object catch (e, st) {
        appLogger.w(
          '[MarketplaceSharedStore] session link failed for ${m.fullName} '
          '($tool): $e',
        );
        appLogger.d(st.toString());
      }
    }
  }

  // ---- One-time sweep (GC) -------------------------------------------------

  /// Replaces stale per-session marketplace clones with a symlink to the shared
  /// flavor dir. A candidate is swept only when it is a real (non-symlink)
  /// directory without TeamPilot's materialization stamp — i.e. a clone made by
  /// the CLI itself — and its session is not in [activeSessionKeys]. Stamped
  /// materializations and active sessions are left untouched.
  Future<void> sweepAll({
    required Iterable<String> workspaceIds,
    Set<String> activeSessionKeys = const {},
  }) async {
    final markets = await PluginRepoService.loadMarketplacesFor(fs, teampilotRoot);
    final byName = {for (final m in markets) m.name.trim(): m};
    if (byName.isEmpty) return;

    final candidates = <_MarketplaceCandidate>[];
    for (final wsId in workspaceIds) {
      final trimmedWs = wsId.trim();
      if (trimmedWs.isEmpty) continue;
      final sessionsDir = WorkspaceLayout(
        teampilotRoot: teampilotRoot,
        fs: fs,
      ).sessionsDir(trimmedWs);
      if (!(await fs.stat(sessionsDir)).isDirectory) continue;
      for (final sessionEntry in await fs.listDir(sessionsDir)) {
        if (!sessionEntry.isDirectory) continue;
        final sessionKey = sessionEntry.name;
        if (sessionKey.isNotEmpty &&
            activeSessionKeys.contains(sessionKey)) {
          continue;
        }
        await _collectSessionMarketplaceCandidates(
          sessionsDir: sessionsDir,
          sessionName: sessionKey,
          marketsByName: byName,
          candidates: candidates,
        );
      }
    }
    for (final candidate in candidates) {
      final paths = pluginManifestPathsForTool(candidate.tool);
      if (paths == null) continue;
      final shared = await ensureShared(
        tool: candidate.tool,
        marketplace: candidate.marketplace,
        paths: paths,
      );
      if (shared == null) continue;
      await _locks.synchronized(
        _linkLockKey(candidate.dest),
        () => _sweepOne(dest: candidate.dest, shared: shared),
      );
    }
  }

  Future<void> _collectSessionMarketplaceCandidates({
    required String sessionsDir,
    required String sessionName,
    required Map<String, PluginMarketplace> marketsByName,
    required List<_MarketplaceCandidate> candidates,
  }) async {
    final runtimeRoot = _ctx.join(sessionsDir, sessionName, 'runtime');
    if (!(await fs.stat(runtimeRoot)).isDirectory) return;
    final configRoots = <String>[];
    // Native CONFIG_DIRs sit at `runtime/<tool>`; mixed seats nest under
    // `runtime/<member>/<tool>`.
    for (final entry in await fs.listDir(runtimeRoot)) {
      if (!entry.isDirectory) continue;
      if (marketplaceConsumerTools.any((t) => t.value == entry.name)) {
        configRoots.add(_ctx.join(runtimeRoot, entry.name));
      } else {
        for (final tool in marketplaceConsumerTools) {
          final nested = _ctx.join(runtimeRoot, entry.name, tool.value);
          if ((await fs.lstat(nested)).isDirectory) {
            configRoots.add(nested);
          }
        }
      }
    }
    for (final configRoot in configRoots) {
      final toolName = _ctx.basename(configRoot);
      final tool = CliTool.tryParse(toolName);
      if (tool == null) continue;
      final marketsDir = _ctx.join(configRoot, 'plugins', 'marketplaces');
      if (!(await fs.stat(marketsDir)).isDirectory) continue;
      for (final entry in await fs.listDir(marketsDir)) {
        if (!entry.isDirectory) continue;
        final marketplace = byNameMatch(marketsByName, entry.name);
        if (marketplace == null) continue;
        final dest = _ctx.join(marketsDir, entry.name);
        final stamp = _ctx.join(
          dest,
          CliPluginProvisionCache.marketplaceSourceStampFileName,
        );
        if ((await fs.stat(stamp)).exists) continue;
        final stat = await fs.lstat(dest);
        if (stat.isSymlink || !stat.isDirectory) continue;
        candidates.add(
          _MarketplaceCandidate(dest: dest, tool: tool, marketplace: marketplace),
        );
      }
    }
  }

  static PluginMarketplace? byNameMatch(
    Map<String, PluginMarketplace> marketsByName,
    String name,
  ) {
    final exact = marketsByName[name.trim()];
    if (exact != null) return exact;
    // Marketplace dir names may carry a `@branch` suffix in some tools.
    final at = name.indexOf('@');
    if (at > 0) {
      final base = name.substring(0, at).trim();
      final baseMatch = marketsByName[base];
      if (baseMatch != null && name.endsWith('@${baseMatch.branch}')) {
        return baseMatch;
      }
    }
    return null;
  }

  Future<void> _sweepOne({required String dest, required String shared}) async {
    final stat = await fs.lstat(dest);
    if (!stat.isDirectory || stat.isSymlink) return;
    final stamp = _ctx.join(
      dest,
      CliPluginProvisionCache.marketplaceSourceStampFileName,
    );
    if ((await fs.stat(stamp)).exists) return;

    await fs.removeRecursive(dest);
    await fs.ensureDir(_ctx.dirname(dest));
    final linked = await fs.createSymlink(target: shared, linkPath: dest);
    if (!linked) {
      await fs.copyTree(source: shared, destination: dest);
    }
  }
}

class _MarketplaceCandidate {
  const _MarketplaceCandidate({
    required this.dest,
    required this.tool,
    required this.marketplace,
  });

  final String dest;
  final CliTool tool;
  final PluginMarketplace marketplace;
}
