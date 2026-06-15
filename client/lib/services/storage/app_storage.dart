import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'runtime_storage_context.dart';

/// Global business storage facade. Requires [RuntimeStorageContext.install].
class AppStorage {
  AppStorage._();

  static RuntimeStorageContext get context => RuntimeStorageContext.current;

  static Filesystem get fs =>
      RuntimeStorageContext.isInstalled
          ? RuntimeStorageContext.current.filesystem
          : LocalFilesystem();

  static AppPaths get paths => RuntimeStorageContext.current.paths;

  static String get home => RuntimeStorageContext.current.home;

  /// Default workspace for new projects and CLI sessions (native: app Documents).
  static String get cwd => RuntimeStorageContext.current.cwd;

  static String get appDataRoot => RuntimeStorageContext.current.appDataRoot;

  static bool get usesPosixPaths => RuntimeStorageContext.current.usesPosixPaths;
}

@immutable
class AppPaths {
  const AppPaths(this.basePath);

  final String basePath;

  p.Context get _ctx => pathContextForDataRoot(basePath);

  String get teamsDir => _ctx.join(basePath, 'teams');

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

  /// UI team JSON under a TeamPilot app-data root ([teamsDir] layout).
  static String teamsUiDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'teams');

  /// Installed skill packages (`manifest.json` + per-skill dirs).
  static String skillsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/installed');

  static String skillBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills/backups');

  static String appProjectsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'projects');

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

  static String teamHubDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub');

  static String teamHubCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/cache');

  static String teamHubRegistriesJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/registries.json');

  static String teamHubFavoritesJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'team-hub/favorites.json');

  static String homeWorkspaceProjectFavoritesJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'home-workspace/project-favorites.json',
      );

  static String homeWorkspaceProjectDisplayPrefsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'home-workspace/project-display-prefs.json',
      );

  static String homeWorkspaceRecentProjectsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'home-workspace/recent-projects.json',
      );

  static String homeWorkspaceClosedProjectsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'home-workspace/closed-projects.json',
      );

  static String homeWorkspaceOpenProjectsJsonForTeampilotRoot(
    String teampilotRoot,
  ) =>
      _pathUnderTeampilotRoot(
        teampilotRoot,
        'home-workspace/open-project-tabs.json',
      );

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
  String get pluginMarketplacesConfigPath =>
      pluginMarketplacesConfigPathForTeampilotRoot(basePath);

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  String get appProjectsDir => _ctx.join(basePath, 'projects');

  String get skillReposConfigPath => skillReposConfigPathForTeampilotRoot(basePath);

  String get teamHubDir => teamHubDirForTeampilotRoot(basePath);
  String get teamHubCacheDir => teamHubCacheDirForTeampilotRoot(basePath);
  String get teamHubRegistriesJson =>
      teamHubRegistriesJsonForTeampilotRoot(basePath);
  String get teamHubFavoritesJson =>
      teamHubFavoritesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceProjectFavoritesJson =>
      homeWorkspaceProjectFavoritesJsonForTeampilotRoot(basePath);

  String get homeWorkspaceProjectDisplayPrefsJson =>
      homeWorkspaceProjectDisplayPrefsJsonForTeampilotRoot(basePath);

  String get homeWorkspaceRecentProjectsJson =>
      homeWorkspaceRecentProjectsJsonForTeampilotRoot(basePath);

  String get homeWorkspaceClosedProjectsJson =>
      homeWorkspaceClosedProjectsJsonForTeampilotRoot(basePath);

  String get homeWorkspaceOpenProjectsJson =>
      homeWorkspaceOpenProjectsJsonForTeampilotRoot(basePath);

  /// Application-level unified provider catalog (`providers/providers.json`).
  String get providerConfigDir => _ctx.join(basePath, 'providers');

  String get providerConfigFile => _ctx.join(providerConfigDir, 'providers.json');

  String get sshProfilesDir => _ctx.join(basePath, 'ssh_profiles');

  /// Team runtime isolation and FlashskyAI / Claude / Codex config profiles.
  String get configProfilesDir => _ctx.join(basePath, 'config-profiles');

  String providerToolDir(String tool, String providerId) =>
      _ctx.join(providerConfigDir, tool.trim(), providerId.trim());

  String codexProviderDir(String providerId) =>
      providerToolDir('codex', providerId);
}

/// Resolves the platform Documents directory for default project [primaryPath].
class DefaultProjectDirectory {
  DefaultProjectDirectory._();

  static String? _cachedPath;

  static Future<String> resolve() async {
    final cached = _cachedPath;
    if (cached != null && cached.isNotEmpty) return cached;
    final dir = await getApplicationDocumentsDirectory();
    await Directory(dir.path).create(recursive: true);
    _cachedPath = dir.path;
    return dir.path;
  }

  /// Working directory of the built-in personal project: `<Documents>/TeamPilot`.
  /// Created on first access so the seeded default project always has a real dir.
  static Future<String> resolveDefaultProjectPath() async {
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
