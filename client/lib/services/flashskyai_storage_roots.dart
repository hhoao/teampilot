import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'io/filesystem.dart';
import 'io/local_filesystem.dart';
import 'io/sftp_filesystem.dart';
import 'io/wsl_filesystem.dart';
import 'remote_file_store.dart';
import 'remote_ssh_storage_paths.dart';
import 'remote_teampilot_app_data_resolver.dart';
import 'ssh_client_factory.dart';

/// Resolved filesystem roots for teams, skills, sessions, and CLI config profiles.
///
/// **Local PTY:** [teampilotRoot] is [AppStorage.basePath].
///
/// **SSH:** [teampilotRoot] is the remote TeamPilot app-data directory
/// (`~/.local/share/com.hhoa.teampilot`, mirroring desktop [AppStorage.basePath]).
/// All CLI runtime data lives under `<teampilotRoot>/config-profiles/`; the
/// legacy `~/.flashskyai` tree is no longer consulted.
class StorageRootsSnapshot {
  StorageRootsSnapshot({
    bool? storageIsRemote,
    required this.teampilotRoot,
    Filesystem? fs,
    CliDataLayout? layout,
    required this.teamsUiDir,
    required this.skillsRoot,
    required this.skillBackupsDir,
    required this.appProjectsDir,
    required this.skillReposConfigPath,
  }) : fs = fs ?? LocalFilesystem(pathContext: p.context),
       layout =
           layout ??
           CliDataLayout(
             teampilotRoot: teampilotRoot,
             fs: fs ?? LocalFilesystem(pathContext: p.context),
           );

  factory StorageRootsSnapshot.local() {
    final paths = AppPathsBootstrapper.current;
    final fs = LocalFilesystem(pathContext: p.context);
    final layout = CliDataLayout(teampilotRoot: paths.basePath, fs: fs);
    return StorageRootsSnapshot(
      teampilotRoot: paths.basePath,
      fs: fs,
      layout: layout,
      teamsUiDir: paths.teamsDir,
      skillsRoot: p.join(paths.basePath, 'skills'),
      skillBackupsDir: p.join(paths.basePath, 'skill-backups'),
      appProjectsDir: paths.appProjectsDir,
      skillReposConfigPath: paths.skillReposConfigPath,
    );
  }

  /// UI app-data root: [AppStorage.basePath] locally; remote XDG app dir on SSH.
  final String teampilotRoot;
  final Filesystem fs;

  final String teamsUiDir;
  final String skillsRoot;
  final String skillBackupsDir;

  /// `projects.json` + `sessions/` (app session index).
  final String appProjectsDir;

  /// Skill marketplace repo list (`skills.json`).
  final String skillReposConfigPath;

  /// CLI runtime layout under `<teampilotRoot>/config-profiles/`.
  final CliDataLayout layout;

  bool get storageIsRemote => fs is SftpFilesystem;
  RemoteFileStore? get remoteFileStore =>
      fs is SftpFilesystem ? (fs as SftpFilesystem).store : null;

  /// Convenience accessor: `<teampilotRoot>/config-profiles/flashskyai/`.
  String get appFlashskyaiDir => layout.appToolRoot('flashskyai');
}

class FlashskyaiStorageRoots {
  FlashskyaiStorageRoots({
    bool Function()? isSshMode,
    SshProfile? Function()? sshProfileResolver,
    SshClientFactory? sshClientFactory,
    RemoteSshStoragePathResolver? remotePathResolver,
    String? Function()? cliExecutableResolver,
  }) : _isSshMode = isSshMode,
       _sshProfileResolver = sshProfileResolver,
       _sshClientFactory = sshClientFactory,
       _remotePathResolver = remotePathResolver,
       _cliExecutableResolver = cliExecutableResolver;

  final bool Function()? _isSshMode;
  final SshProfile? Function()? _sshProfileResolver;
  final SshClientFactory? _sshClientFactory;
  final RemoteSshStoragePathResolver? _remotePathResolver;
  final String? Function()? _cliExecutableResolver;

  StorageRootsSnapshot? _cache;
  Future<StorageRootsSnapshot>? _inflight;

  /// Clears the resolved snapshot (call after SSH profile or connection mode changes).
  void invalidate() {
    _cache = null;
    _inflight = null;
  }

  Future<StorageRootsSnapshot> resolve({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache!;
    if (!forceRefresh && _inflight != null) return _inflight!;
    final future = _resolveUncached();
    _inflight = future;
    try {
      final snap = await future;
      _cache = snap;
      return snap;
    } finally {
      if (identical(_inflight, future)) {
        _inflight = null;
      }
    }
  }

  Future<StorageRootsSnapshot> _resolveUncached() async {
    if (!(_isSshMode?.call() ?? false)) {
      return _localSnapshot();
    }
    final profile = _sshProfileResolver?.call();
    final factory = _sshClientFactory;
    if (profile == null || factory == null) {
      return _localSnapshot();
    }

    final pathResolver =
        _remotePathResolver ??
        RemoteSshStoragePathResolver(clientFactory: factory);
    final paths = await pathResolver.resolve(profile);
    if (paths == null) {
      return _localSnapshot();
    }

    final fileStore = RemoteFileStore(profile: profile, clientFactory: factory);

    // Warm the shared SFTP channel before parallel stat probes.
    await factory.sftpFor(profile);

    final primaryTeampilot = paths.teampilotAppDir;
    final legacyTeampilot = AppPaths.defaultTeampilotAppDataDirForHome(
      paths.home,
    );
    var teampilot = primaryTeampilot;
    if (primaryTeampilot != legacyTeampilot) {
      final exists = await Future.wait([
        RemoteTeampilotAppDataResolver.teampilotTreeHasData(
          fileStore.fileExists,
          primaryTeampilot,
        ),
        RemoteTeampilotAppDataResolver.teampilotTreeHasData(
          fileStore.fileExists,
          legacyTeampilot,
        ),
      ]);
      if (!exists[0] && exists[1]) teampilot = legacyTeampilot;
    }

    final fs = SftpFilesystem(fileStore);
    final layout = CliDataLayout(teampilotRoot: teampilot, fs: fs);
    return StorageRootsSnapshot(
      teampilotRoot: teampilot,
      fs: fs,
      layout: layout,
      teamsUiDir: AppPaths.teamsUiDirForTeampilotRoot(teampilot),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(teampilot),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(teampilot),
      appProjectsDir: AppPaths.appProjectsDirForTeampilotRoot(teampilot),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(
        teampilot,
      ),
    );
  }

  StorageRootsSnapshot _localSnapshot() {
    final paths = AppPathsBootstrapper.current;
    final executable = _cliExecutableResolver?.call()?.trim() ?? '';
    final fs = executable.startsWith('wsl ')
        ? WslFilesystem(distro: _parseWslDistro(executable))
        : LocalFilesystem(pathContext: p.context);
    final layout = CliDataLayout(teampilotRoot: paths.basePath, fs: fs);
    return StorageRootsSnapshot(
      teampilotRoot: paths.basePath,
      fs: fs,
      layout: layout,
      teamsUiDir: paths.teamsDir,
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(paths.basePath),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(paths.basePath),
      appProjectsDir: paths.appProjectsDir,
      skillReposConfigPath: paths.skillReposConfigPath,
    );
  }

  static String? _parseWslDistro(String executable) {
    final parts = executable.split(RegExp(r'\s+'));
    for (var i = 0; i < parts.length - 1; i++) {
      if (parts[i] == '-d' || parts[i] == '--distribution') {
        final distro = parts[i + 1].trim();
        return distro.isEmpty ? null : distro;
      }
    }
    return null;
  }
}
