import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

@immutable
class AppPaths {
  const AppPaths(this.basePath);

  final String basePath;

  String get teamsDir => p.join(basePath, 'teams');

  /// Linux desktop / `path_provider` app-data id (e.g. `~/.local/share/com.hhoa.teampilot`).
  static const teampilotAppDataDirName = 'com.hhoa.teampilot';

  /// Default TeamPilot UI data root for a remote POSIX home (matches [basePath] on desktop).
  static String defaultTeampilotAppDataDirForHome(String home) =>
      p.join(home, '.local', 'share', teampilotAppDataDirName);

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
      p.join(teampilotRoot, 'skill-repo-cache');

  String get skillRepoCacheDir => skillRepoCacheDirForTeampilotRoot(basePath);

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  String get appProjectsDir => p.join(basePath, 'projects');

  String get skillReposConfigPath => p.join(basePath, 'skills.json');

  /// Application-level unified provider catalog (`providers/providers.json`).
  String get providerConfigDir => p.join(basePath, 'providers');

  String get providerConfigFile => p.join(providerConfigDir, 'providers.json');

  /// Team runtime isolation and FlashskyAI / Claude / Codex config profiles.
  String get configProfilesDir => p.join(basePath, 'config-profiles');

  String providerToolDir(String tool, String providerId) =>
      p.join(providerConfigDir, tool.trim(), providerId.trim());

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
    _current = AppPaths(dir.path);
  }

  @visibleForTesting
  static void setCurrentForTesting(AppPaths paths) {
    _current = paths;
  }

  @visibleForTesting
  static void resetForTesting() {
    _current = null;
  }
}
