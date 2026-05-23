import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'io/filesystem.dart';
import 'io/local_filesystem.dart';
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

  static String skillsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills');

  static String skillBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skill-backups');

  static String appProjectsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'projects');

  static String skillReposConfigPathForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skills.json');

  /// Local disk cache for GitHub skill repos (tarball files + discovered skills).
  static String skillRepoCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'skill-repo-cache');

  static String pluginsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins');

  static String pluginBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-backups');

  static String pluginsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins.json');

  static String pluginMarketplacesConfigPathForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-marketplaces.json');

  static String pluginMarketplaceCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-marketplace-cache');

  String get skillRepoCacheDir => skillRepoCacheDirForTeampilotRoot(basePath);

  String get pluginMarketplaceCacheDir =>
      pluginMarketplaceCacheDirForTeampilotRoot(basePath);

  String get pluginsJson => _ctx.join(basePath, 'plugins.json');
  String get pluginMarketplacesConfigPath => _ctx.join(basePath, 'plugin-marketplaces.json');

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  String get appProjectsDir => _ctx.join(basePath, 'projects');

  String get skillReposConfigPath => _ctx.join(basePath, 'skills.json');

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
