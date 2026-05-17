import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'launch_command_builder.dart';

class AppStorage {
  AppStorage._();

  static String? _basePath;
  static String? _cliDataRootOverride;

  static String get basePath => _basePath ?? '.';

  /// Root of the CLI-owned data directory (`~/.flashskyai`). Shared with the
  /// `flashskyai` CLI: sessions, history, and the canonical team configs all
  /// live under here.
  ///
  /// On Android there is no local CLI — data lives on the remote SSH host.
  /// All CLI paths are sandboxed under the app's data directory so writes
  /// never hit the read-only root filesystem.
  static String get flashskyaiDataDir {
    if (Platform.isAndroid) {
      return p.join(basePath, '.flashskyai');
    }
    return p.join(
      _cliDataRootOverride ??
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '',
      '.flashskyai',
    );
  }

  /// CLI's `teams/` directory. UI imports from here on startup.
  static String get cliTeamsDir => p.join(flashskyaiDataDir, 'teams');

  /// CLI's active session descriptors (`sessions/<uuid>.json`).
  static String get cliSessionsDir => p.join(flashskyaiDataDir, 'sessions');

  static String get cliProjectsDir => p.join(flashskyaiDataDir, 'projects');

  /// Bucket folder name the CLI uses under `projects/` for a workspace path
  /// (e.g. `/home/hhoa/agent` → `-home-hhoa-agent`,
  /// `D:\repo` → `-mnt-d-repo`).
  static String cliProjectBucketForPrimaryPath(String primaryPath) {
    var s = primaryPath.trim().replaceAll('\\', '/');
    if (s.isEmpty) return '';
    // Match CLI layout: POSIX paths as-is; drive letters as /mnt/<drive>/...
    final wslStyle = LaunchCommandBuilder.windowsPathToWsl(s);
    if (wslStyle != null) {
      s = wslStyle;
    } else if (!s.startsWith('/')) {
      s = p.normalize(s).replaceAll('\\', '/');
    }
    if (s == '.' || s == '/') return '';
    return s.replaceAll('/', '-');
  }

  /// True when the CLI has persisted state for [sessionId] under the flashskyai
  /// data root: `sessions/<id>.json`, or `projects/<bucket>/<id>.jsonl` / a
  /// directory `projects/<bucket>/<id>/`.
  ///
  /// [primaryPath] is used to resolve `projects/<bucket>/` in O(1); if it does
  /// not match the on-disk bucket, a shallow scan of [cliProjectsDir] is used
  /// as a fallback (few subdirectories per machine).
  ///
  /// [dataRoot] defaults to [flashskyaiDataDir]; tests may pass a temp tree.
  static bool cliSessionDescriptorExists(
    String sessionId,
    String primaryPath, {
    String? dataRoot,
  }) {
    final id = sessionId.trim();
    if (id.isEmpty) return false;
    final root = (dataRoot != null && dataRoot.trim().isNotEmpty)
        ? dataRoot.trim()
        : flashskyaiDataDir;
    final sessionsDir = p.join(root, 'sessions');
    final projectsDir = p.join(root, 'projects');

    if (File(p.join(sessionsDir, '$id.json')).existsSync()) return true;

    final slug = cliProjectBucketForPrimaryPath(primaryPath);
    if (slug.isNotEmpty) {
      final bucket = p.join(projectsDir, slug);
      if (File(p.join(bucket, '$id.jsonl')).existsSync()) return true;
      if (Directory(p.join(bucket, id)).existsSync()) return true;
    }

    return _cliProjectsScanForSession(projectsDir, id);
  }

  static bool _cliProjectsScanForSession(String projectsDir, String sessionId) {
    final root = Directory(projectsDir);
    if (!root.existsSync()) return false;
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final bucketPath = entity.path;
        if (File(p.join(bucketPath, '$sessionId.jsonl')).existsSync()) {
          return true;
        }
        if (Directory(p.join(bucketPath, sessionId)).existsSync()) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  /// CLI's session history log (legacy). Session metadata lives in [appProjectsDir];
  /// do not use this path for app-owned session state.
  @Deprecated(
    'Use appProjectsDir + SessionRepository; CLI history is not the session index.',
  )
  static String get cliHistoryPath =>
      p.join(flashskyaiDataDir, 'history.jsonl');

  /// UI-owned teams directory (`<appData>/teams` on device; on SSH hosts
  /// [teamsUiDirForCliData] under `~/.flashskyai/teampilot/teams`).
  static String get teamsDir => p.join(basePath, 'teams');

  /// Linux desktop / `path_provider` app-data id (e.g. `~/.local/share/com.hhoa.teampilot`).
  static const teampilotAppDataDirName = 'com.hhoa.teampilot';

  /// Default TeamPilot UI data root for a remote POSIX home (matches [basePath] on desktop).
  static String defaultTeampilotAppDataDirForHome(String home) =>
      p.join(home, '.local', 'share', teampilotAppDataDirName);

  /// Legacy SSH layout nested under the CLI data dir (`~/.flashskyai/teampilot`).
  static String teampilotDirForCliData(String cliDataDir) =>
      p.join(cliDataDir, 'teampilot');

  /// UI team JSON under a TeamPilot app-data root ([teamsDir] layout).
  static String teamsUiDirForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'teams');

  static String skillsDirForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'skills');

  static String skillBackupsDirForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'skill-backups');

  static String appProjectsDirForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'projects');

  static String skillReposConfigPathForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'skills.json');

  static String tempTeamRegistryPathForTeampilotRoot(String teampilotRoot) =>
      p.join(teampilotRoot, 'ui-temp-teams.json');

  @Deprecated('Use teampilot app-data root helpers (teamsUiDirForTeampilotRoot)')
  static String teamsUiDirForCliData(String cliDataDir) =>
      teamsUiDirForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  @Deprecated('Use teampilot app-data root helpers')
  static String skillsDirForCliData(String cliDataDir) =>
      skillsDirForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  @Deprecated('Use teampilot app-data root helpers')
  static String skillBackupsDirForCliData(String cliDataDir) =>
      skillBackupsDirForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  @Deprecated('Use teampilot app-data root helpers')
  static String appProjectsDirForCliData(String cliDataDir) =>
      appProjectsDirForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  @Deprecated('Use teampilot app-data root helpers')
  static String skillReposConfigPathForCliData(String cliDataDir) =>
      skillReposConfigPathForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  @Deprecated('Use teampilot app-data root helpers')
  static String tempTeamRegistryPathForCliData(String cliDataDir) =>
      tempTeamRegistryPathForTeampilotRoot(teampilotDirForCliData(cliDataDir));

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  static String get appProjectsDir => p.join(basePath, 'projects');

  static String get skillReposConfigPath => p.join(basePath, 'skills.json');

  static String get tempTeamRegistryPath =>
      p.join(basePath, 'ui-temp-teams.json');

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
  }

  static Future<void> useWslCliDataDirIfNeeded(String? cliExecutable) async {
    if (!Platform.isWindows) return;
    final trimmed = cliExecutable?.trim().toLowerCase() ?? '';
    if (!trimmed.startsWith('wsl ') && !trimmed.startsWith('wsl.exe ')) {
      return;
    }
    try {
      final result = await Process.run('wsl.exe', [
        'wslpath',
        '-w',
        r'~/.flashskyai',
      ]);
      if (result.exitCode != 0 || result.stdout is! String) return;
      final path = (result.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      if (path.isEmpty) return;
      _cliDataRootOverride = path.endsWith(r'\.flashskyai')
          ? path.substring(0, path.length - r'\.flashskyai'.length)
          : path;
    } on Object {
      // Keep the native Windows data directory if WSL is unavailable here.
    }
  }
}
