import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'runtime_context.dart';

/// Global business storage facade for the **control plane**: forwards to the
/// bound home [RuntimeContext]. Bind once at bootstrap via [bindHome]
/// (`RuntimeContextRegistry` pushes its `home()` here). Work-plane consumers
/// resolve their own context via the registry instead of this facade.
class AppStorage {
  AppStorage._();

  static RuntimeContext? _home;

  /// Bind the home context (control plane). Synchronous so test setup stays
  /// non-async; the registry calls this after ensureHome/rebindHome.
  static void bindHome(RuntimeContext home) => _home = home;

  static void unbindHome() => _home = null;

  static bool get isInstalled => _home != null;

  static RuntimeContext get context =>
      _home ??
      (throw StateError(
        'AppStorage home not bound; call AppStorage.bindHome() at bootstrap.',
      ));

  static Filesystem get fs => _home?.filesystem ?? LocalFilesystem();

  static AppPaths get paths => context.paths;

  static String get home => context.home;

  /// Default workspace for new workspaces and CLI sessions (native: app Documents).
  static String get cwd => context.cwd;

  static String get appDataRoot => context.appDataRoot;

  static bool get usesPosixPaths => context.usesPosixPaths;

  /// Test seam: bind a native home context rooted at [paths] (replaces the old
  /// the removed global storage singleton install).
  @visibleForTesting
  static void installForTesting({
    required Filesystem filesystem,
    required AppPaths paths,
    String home = '/home/test',
    String cwd = '/home/test',
  }) {
    bindHome(
      RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: filesystem,
        home: home,
        cwd: cwd,
        appDataRoot: paths.basePath,
        paths: paths,
      ),
    );
    AppPathsBootstrapper.syncPaths(paths);
  }

  @visibleForTesting
  static void resetForTesting() => unbindHome();
}

@immutable
class AppPaths {
  const AppPaths(this.basePath);

  final String basePath;

  p.Context get _ctx => pathContextForDataRoot(basePath);

  String get launchProfilesDir => _ctx.join(basePath, 'launch-profiles');

  String get extensionsStateJson =>
      _ctx.join(basePath, 'extensions', 'state.json');

  String get notificationsJson =>
      notificationsJsonForTeampilotRoot(basePath);

  String get cliPresetsJson =>
      _ctx.join(basePath, 'cli-presets.json');

  /// Linux desktop / `path_provider` app-data id (e.g. `~/.local/share/com.hhoa.teampilot`).
  static const teampilotAppDataDirName = 'com.hhoa.teampilot';

  /// Default TeamPilot UI data root for a remote POSIX home (matches [basePath] on desktop).
  static String defaultTeampilotAppDataDirForHome(String home) =>
      pathContextForDataRoot(home).join(
        home,
        '.local',
        'share',
        teampilotAppDataDirName,
      );

  static p.Context get posixPathContext => p.Context(style: p.Style.posix);

  /// POSIX-style roots (remote SSH paths, in-memory `/tp` tests) must not use
  /// the host [p.context] on Windows — otherwise joins emit `\` separators.
  static p.Context pathContextForDataRoot(String root) {
    final trimmed = root.trim();
    if (trimmed.startsWith('/') ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith('//')) {
      return posixPathContext;
    }
    return p.context;
  }

  /// Parent of `skills/installed` or `plugins/installed`.
  static String teampilotRootFromInstalledScopeDir(String installedScopeDir) {
    final ctx = pathContextForDataRoot(installedScopeDir);
    if (ctx.basename(installedScopeDir) != 'installed') {
      throw ArgumentError.value(
        installedScopeDir,
        'installedScopeDir',
        'must be a skills/installed or plugins/installed directory',
      );
    }
    return ctx.dirname(ctx.dirname(installedScopeDir));
  }

  /// Joins under [root], using POSIX separators when [root] is a remote path.
  static String _pathUnderTeampilotRoot(String teampilotRoot, String segment) {
    if (teampilotRoot.startsWith('/')) {
      return posixPathContext.join(teampilotRoot, segment);
    }
    return p.join(teampilotRoot, segment);
  }

  /// UI identity JSON under a TeamPilot app-data root ([launchProfilesDir] layout).
  static String launchProfilesDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'launch-profiles');

  /// Installed skill packages (`manifest.json` + per-skill dirs).
  static String skillsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/installed');

  static String skillBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/backups');

  static String workspaceDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'workspace');

  static String cliDefaultsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'cli-defaults');

  /// Skill marketplace repo list.
  static String skillReposConfigPathForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/repos.json');

  /// Local disk cache for GitHub skill repos (tarball files + discovered skills).
  static String skillRepoCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/repo-cache');

  /// Installed plugin bundles.
  static String pluginsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/installed');

  static String pluginBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/backups');

  static String pluginsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/plugins.json');

  static String extensionsStateJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'extensions/state.json');

  static String notificationsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'notifications.json');

  static String pluginMarketplacesConfigPathForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/marketplaces.json');

  static String pluginMarketplaceCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/marketplace-cache');

  static String pluginExternalCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins/external-cache');

  /// Global MCP server catalog (`mcp/mcp_servers.json`).
  static String mcpServersJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'mcp/mcp_servers.json');

  static String mcpRegistrySourcesConfigPathForTeampilotRoot(
    String teampilotRoot,
  ) => _pathUnderTeampilotRoot(teampilotRoot, 'mcp/registry_sources.json');

  static String mcpBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'mcp/backups');

  /// Cached MCP discovery listings from remote catalogs (Smithery / official).
  static String mcpDiscoveryCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'mcp/discovery-cache');

  static String teamHubDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub');

  static String teamHubCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/cache');

  static String teamHubRegistriesJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/registries.json');

  static String teamHubFavoritesJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/favorites.json');

  static String homeWorkspaceWorkspaceFavoritesJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'ui/workspace-favorites.json');

  static String homeWorkspaceWorkspaceDisplayPrefsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'ui/workspace-display-prefs.json',
      );

  static String homeWorkspaceWorkspaceLaunchPrefsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'ui/workspace-launch-prefs.json',
      );

  static String homeWorkspaceRecentWorkspacesJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'ui/recent-workspaces.json');

  static String homeWorkspaceClosedWorkspacesJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'ui/closed-workspaces.json');

  static String homeWorkspaceOpenWorkspacesJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'ui/open-workspace-tabs.json');

  String get skillRepoCacheDir => skillRepoCacheDirForTeampilotRoot(basePath);

  String get pluginMarketplaceCacheDir =>
      pluginMarketplaceCacheDirForTeampilotRoot(basePath);

  String get pluginExternalCacheDir =>
      pluginExternalCacheDirForTeampilotRoot(basePath);

  String get pluginsJson => pluginsJsonForTeampilotRoot(basePath);
  String get mcpServersJson => mcpServersJsonForTeampilotRoot(basePath);

  String get mcpRegistrySourcesConfigPath =>
      mcpRegistrySourcesConfigPathForTeampilotRoot(basePath);
  String get mcpBackupsDir => mcpBackupsDirForTeampilotRoot(basePath);
  String get mcpDiscoveryCacheDir =>
      mcpDiscoveryCacheDirForTeampilotRoot(basePath);
  String get pluginMarketplacesConfigPath =>
      pluginMarketplacesConfigPathForTeampilotRoot(basePath);

  /// Workbench entities: `workspace/workspaces/{id}/manifest.json`, sessions, bus.
  String get workspaceDir => _ctx.join(basePath, 'workspace');

  /// App-wide CLI default trees (`cli-defaults/{tool}/`).
  String get cliDefaultsDir => _ctx.join(basePath, 'cli-defaults');

  String get skillReposConfigPath => skillReposConfigPathForTeampilotRoot(basePath);

  String get teamHubDir => teamHubDirForTeampilotRoot(basePath);
  String get teamHubCacheDir => teamHubCacheDirForTeampilotRoot(basePath);
  String get teamHubRegistriesJson =>
      teamHubRegistriesJsonForTeampilotRoot(basePath);
  String get teamHubFavoritesJson =>
      teamHubFavoritesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceWorkspaceFavoritesJson =>
      homeWorkspaceWorkspaceFavoritesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceWorkspaceDisplayPrefsJson =>
      homeWorkspaceWorkspaceDisplayPrefsJsonForTeampilotRoot(basePath);

  String get homeWorkspaceWorkspaceLaunchPrefsJson =>
      homeWorkspaceWorkspaceLaunchPrefsJsonForTeampilotRoot(basePath);

  String get homeWorkspaceRecentWorkspacesJson =>
      homeWorkspaceRecentWorkspacesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceClosedWorkspacesJson =>
      homeWorkspaceClosedWorkspacesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceOpenWorkspacesJson =>
      homeWorkspaceOpenWorkspacesJsonForTeampilotRoot(basePath);

  static String worktreeUiPrefsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'ui/worktree-ui-prefs.json');

  String get worktreeUiPrefsJson =>
      worktreeUiPrefsJsonForTeampilotRoot(basePath);

  /// Application-level unified provider catalog (`providers/providers.json`).
  String get providerConfigDir => _ctx.join(basePath, 'providers');

  String get providerConfigFile => _ctx.join(providerConfigDir, 'providers.json');

  String get sshProfilesDir => _ctx.join(basePath, 'ssh_profiles');

  /// Control-plane runtime targets registry (`targets.json`). Holds the
  /// authoritative `defaultTargetId`, persisted ssh targets, and WSL distro.
  String get targetsFile => _ctx.join(basePath, 'targets.json');

  String providerToolDir(String tool, String providerId) =>
      _ctx.join(providerConfigDir, tool.trim(), providerId.trim());

  String codexProviderDir(String providerId) =>
      providerToolDir('codex', providerId);
}

/// Resolves the platform Documents directory for default workspace [primaryPath].
class DefaultWorkspaceDirectory {
  DefaultWorkspaceDirectory._();

  static const _prefsKey = 'teampilot.default_documents_directory_path';

  static String? _cachedPath;

  /// Resolves the OS Documents folder used as the default workspace parent.
  ///
  /// On cold start, [getApplicationDocumentsDirectory] can take ~1–2s on Linux
  /// (portal/DBus). We prefer a persisted path, then a platform fast path, and
  /// only fall back to path_provider when needed.
  static Future<String> resolve({SharedPreferences? preferences}) async {
    final cached = _cachedPath;
    if (cached != null && cached.isNotEmpty) return cached;

    final prefs = preferences;
    if (prefs != null) {
      final persisted = prefs.getString(_prefsKey)?.trim();
      if (persisted != null && persisted.isNotEmpty && _directoryExists(persisted)) {
        _cachedPath = persisted;
        return persisted;
      }
    }

    final fast = _platformDocumentsFastPath();
    if (fast != null && _directoryExists(fast)) {
      await Directory(fast).create(recursive: true);
      _cachedPath = fast;
      await prefs?.setString(_prefsKey, fast);
      return fast;
    }

    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    _cachedPath = dir.path;
    await prefs?.setString(_prefsKey, dir.path);
    return dir.path;
  }

  static bool _directoryExists(String path) {
    try {
      return Directory(path).existsSync();
    } on Object {
      return false;
    }
  }

  @visibleForTesting
  static String? platformDocumentsFastPathForTesting() =>
      _platformDocumentsFastPath();

  static String? _platformDocumentsFastPath() {
    if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_DOCUMENTS_DIR']?.trim();
      if (xdg != null && xdg.isNotEmpty) return xdg;
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) return p.join(home, 'Documents');
      return null;
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) return p.join(home, 'Documents');
      return null;
    }
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE']?.trim();
      if (userProfile != null && userProfile.isNotEmpty) {
        return p.join(userProfile, 'Documents');
      }
    }
    return null;
  }

  /// Working directory of the built-in personal workspace: `<Documents>/TeamPilot`.
  /// Created on first access so the seeded default workspace always has a real dir.
  static Future<String> resolveDefaultWorkspacePath() async {
    final docs = await resolve();
    final path = p.join(docs, 'TeamPilot');
    await Directory(path).create(recursive: true);
    return path;
  }

  @visibleForTesting
  static void setForTesting(String path) {
    _cachedPath = path;
  }

  @visibleForTesting
  static void resetForTesting() {
    _cachedPath = null;
  }
}

class AppPathsBootstrapper {
  AppPathsBootstrapper._();

  static AppPaths? _current;

  static bool get isInitialized => _current != null;

  static AppPaths get current {
    final paths = _current;
    if (paths == null || paths.basePath.isEmpty) {
      throw StateError(
        'AppPathsBootstrapper.init() must be called before using application data paths.',
      );
    }
    return paths;
  }

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    syncPaths(AppPaths(dir.path));
  }

  static void syncPaths(AppPaths paths) {
    _current = paths;
  }

  @visibleForTesting
  static void setCurrentForTesting(AppPaths paths) {
    syncPaths(paths);
  }

  @visibleForTesting
  static void resetForTesting() {
    _current = null;
  }
}
