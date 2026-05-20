import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
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
    required this.storageIsRemote,
    required this.teampilotRoot,
    required this.teamsUiDir,
    required this.skillsRoot,
    required this.skillBackupsDir,
    required this.appProjectsDir,
    required this.skillReposConfigPath,
    this.remoteFileStore,
    CliDataLayout? layout,
  }) : layout =
           layout ??
           CliDataLayout(
             teampilotRoot: teampilotRoot,
             createDirectory: remoteFileStore?.ensureDirectory,
             createSymlink: remoteFileStore == null
                 ? null
                 : ({required String target, required String linkPath}) async {
                     await remoteFileStore.createSymlink(
                       target: target,
                       linkPath: linkPath,
                     );
                     return true;
                   },
           );

  factory StorageRootsSnapshot.local() {
    return StorageRootsSnapshot(
      storageIsRemote: false,
      teampilotRoot: AppStorage.basePath,
      teamsUiDir: AppStorage.teamsDir,
      skillsRoot: p.join(AppStorage.basePath, 'skills'),
      skillBackupsDir: p.join(AppStorage.basePath, 'skill-backups'),
      appProjectsDir: AppStorage.appProjectsDir,
      skillReposConfigPath: AppStorage.skillReposConfigPath,
    );
  }

  final bool storageIsRemote;

  /// UI app-data root: [AppStorage.basePath] locally; remote XDG app dir on SSH.
  final String teampilotRoot;

  final String teamsUiDir;
  final String skillsRoot;
  final String skillBackupsDir;

  /// `projects.json` + `sessions/` (app session index).
  final String appProjectsDir;

  /// Skill marketplace repo list (`skills.json`).
  final String skillReposConfigPath;

  final RemoteFileStore? remoteFileStore;

  /// CLI runtime layout under `<teampilotRoot>/config-profiles/`.
  final CliDataLayout layout;

  /// Convenience accessor: `<teampilotRoot>/config-profiles/flashskyai/`.
  String get appFlashskyaiDir => layout.appToolRoot('flashskyai');
}

class FlashskyaiStorageRoots {
  FlashskyaiStorageRoots({
    bool Function()? isSshMode,
    SshProfile? Function()? sshProfileResolver,
    SshClientFactory? sshClientFactory,
    RemoteSshStoragePathResolver? remotePathResolver,
  }) : _isSshMode = isSshMode,
       _sshProfileResolver = sshProfileResolver,
       _sshClientFactory = sshClientFactory,
       _remotePathResolver = remotePathResolver;

  final bool Function()? _isSshMode;
  final SshProfile? Function()? _sshProfileResolver;
  final SshClientFactory? _sshClientFactory;
  final RemoteSshStoragePathResolver? _remotePathResolver;

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
      return StorageRootsSnapshot.local();
    }
    final profile = _sshProfileResolver?.call();
    final factory = _sshClientFactory;
    if (profile == null || factory == null) {
      return StorageRootsSnapshot.local();
    }

    final pathResolver =
        _remotePathResolver ??
        RemoteSshStoragePathResolver(clientFactory: factory);
    final paths = await pathResolver.resolve(profile);
    if (paths == null) {
      return StorageRootsSnapshot.local();
    }

    final fileStore = RemoteFileStore(profile: profile, clientFactory: factory);

    // Warm the shared SFTP channel before parallel stat probes.
    await factory.sftpFor(profile);

    final primaryTeampilot = paths.teampilotAppDir;
    final legacyTeampilot =
        AppStorage.defaultTeampilotAppDataDirForHome(paths.home);
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

    return StorageRootsSnapshot(
      storageIsRemote: true,
      teampilotRoot: teampilot,
      teamsUiDir: AppStorage.teamsUiDirForTeampilotRoot(teampilot),
      skillsRoot: AppStorage.skillsDirForTeampilotRoot(teampilot),
      skillBackupsDir: AppStorage.skillBackupsDirForTeampilotRoot(teampilot),
      appProjectsDir: AppStorage.appProjectsDirForTeampilotRoot(teampilot),
      skillReposConfigPath: AppStorage.skillReposConfigPathForTeampilotRoot(
        teampilot,
      ),
      remoteFileStore: fileStore,
    );
  }
}
