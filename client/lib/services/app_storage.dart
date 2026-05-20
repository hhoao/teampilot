import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorage {
  AppStorage._();

  static String? _basePath;

  static bool get isInitialized => _basePath != null && _basePath!.isNotEmpty;

  static String get basePath {
    final path = _basePath;
    if (path == null || path.isEmpty) {
      throw StateError(
        'AppStorage.init() must be called before using application data paths.',
      );
    }
    return path;
  }

  @visibleForTesting
  static void setBasePathForTesting(String path) {
    _basePath = path;
  }

  @visibleForTesting
  static void resetForTesting() {
    _basePath = null;
  }

  /// UI-owned teams directory (`<appData>/teams` on device; on SSH hosts
  /// [teamsUiDirForTeampilotRoot] under the remote TeamPilot app-data dir).
  static String get teamsDir => p.join(basePath, 'teams');

  /// Linux desktop / `path_provider` app-data id (e.g. `~/.local/share/com.hhoa.teampilot`).
  static const teampilotAppDataDirName = 'com.hhoa.teampilot';

  /// Default TeamPilot UI data root for a remote POSIX home (matches [basePath] on desktop).
  static String defaultTeampilotAppDataDirForHome(String home) =>
      p.join(home, '.local', 'share', teampilotAppDataDirName);

  static p.Context get _posixPathContext => p.Context(style: p.Style.posix);

  /// Joins under [root], using POSIX separators when [root] is a remote path.
  static String _pathUnderTeampilotRoot(String teampilotRoot, String segment) {
    if (teampilotRoot.startsWith('/')) {
      return _posixPathContext.join(teampilotRoot, segment);
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

  static String get skillRepoCacheDir =>
      skillRepoCacheDirForTeampilotRoot(basePath);

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  static String get appProjectsDir => p.join(basePath, 'projects');

  static String get skillReposConfigPath => p.join(basePath, 'skills.json');

  /// Application-level unified provider catalog (`providers/providers.json`).
  static String get providerConfigDir => p.join(basePath, 'providers');

  static String get providerConfigFile =>
      p.join(providerConfigDir, 'providers.json');

  /// Team runtime isolation and FlashskyAI / Claude / Codex config profiles.
  static String get configProfilesDir => p.join(basePath, 'config-profiles');

  static String providerToolDir(String tool, String providerId) =>
      p.join(providerConfigDir, tool.trim(), providerId.trim());

  static String codexProviderDir(String providerId) =>
      providerToolDir('codex', providerId);

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
  }
}
