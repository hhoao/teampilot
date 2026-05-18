import 'package:path/path.dart' as p;

import '../models/ssh_profile.dart';
import 'app_storage.dart';
import 'remote_file_store.dart';
import 'remote_ssh_storage_paths.dart';
import 'remote_teampilot_app_data_resolver.dart';
import 'ssh_client_factory.dart';

/// Resolved filesystem roots for teams, skills, sessions, and CLI data.
///
/// **Local PTY:** [teampilotRoot] is [AppStorage.basePath] (same layout as desktop).
///
/// **SSH:** [teampilotRoot] is the remote TeamPilot app-data directory
/// (`~/.local/share/com.hhoa.teampilot`, same as desktop [AppStorage.basePath]).
/// CLI-owned trees still use [remoteCliDataDir] (`~/.flashskyai`).
class StorageRootsSnapshot {
  const StorageRootsSnapshot({
    required this.storageIsRemote,
    required this.teampilotRoot,
    required this.teamsUiDir,
    required this.cliTeamsDir,
    required this.skillsRoot,
    required this.skillBackupsDir,
    required this.cliSkillsDir,
    required this.cliAgentsDir,
    required this.appProjectsDir,
    required this.skillReposConfigPath,
    required this.tempTeamRegistryPath,
    this.remoteFileStore,
    this.remoteCliDataDir,
  });

  factory StorageRootsSnapshot.local() {
    return StorageRootsSnapshot(
      storageIsRemote: false,
      teampilotRoot: AppStorage.basePath,
      teamsUiDir: AppStorage.teamsDir,
      cliTeamsDir: AppStorage.cliTeamsDir,
      skillsRoot: p.join(AppStorage.basePath, 'skills'),
      skillBackupsDir: p.join(AppStorage.basePath, 'skill-backups'),
      cliSkillsDir: p.join(AppStorage.flashskyaiDataDir, 'skills'),
      cliAgentsDir: AppStorage.cliAgentsDir,
      appProjectsDir: AppStorage.appProjectsDir,
      skillReposConfigPath: AppStorage.skillReposConfigPath,
      tempTeamRegistryPath: AppStorage.tempTeamRegistryPath,
    );
  }

  final bool storageIsRemote;

  /// UI app-data root: [AppStorage.basePath] locally; remote XDG app dir on SSH.
  final String teampilotRoot;

  final String teamsUiDir;
  final String cliTeamsDir;
  final String skillsRoot;
  final String skillBackupsDir;
  final String cliSkillsDir;

  /// User agent markdown under the CLI data root (`agents/*.md`).
  final String cliAgentsDir;

  /// `projects.json` + `sessions/` (app session index).
  final String appProjectsDir;

  /// Skill marketplace repo list (`skills.json`).
  final String skillReposConfigPath;

  /// Registry of UI-created temp CLI team folder names.
  final String tempTeamRegistryPath;

  final RemoteFileStore? remoteFileStore;
  final String? remoteCliDataDir;

  @Deprecated('Use storageIsRemote')
  bool get cliStorageIsRemote => storageIsRemote;

  @Deprecated('Use storageIsRemote')
  bool get isRemote => storageIsRemote;
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

    final dataDir = paths.cliDataDir;
    final posix = p.Context(style: p.Style.posix);
    final fileStore = RemoteFileStore(profile: profile, clientFactory: factory);

    // Warm the shared SFTP channel before parallel stat probes.
    await factory.sftpFor(profile);

    final primaryTeampilot = paths.teampilotAppDir;
    final legacyTeampilot =
        RemoteTeampilotAppDataResolver.legacyTeampilotRootForCliData(dataDir);
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
      cliTeamsDir: posix.join(dataDir, 'teams'),
      skillsRoot: AppStorage.skillsDirForTeampilotRoot(teampilot),
      skillBackupsDir: AppStorage.skillBackupsDirForTeampilotRoot(teampilot),
      cliSkillsDir: posix.join(dataDir, 'skills'),
      cliAgentsDir: posix.join(dataDir, 'agents'),
      appProjectsDir: AppStorage.appProjectsDirForTeampilotRoot(teampilot),
      skillReposConfigPath: AppStorage.skillReposConfigPathForTeampilotRoot(
        teampilot,
      ),
      tempTeamRegistryPath: AppStorage.tempTeamRegistryPathForTeampilotRoot(
        teampilot,
      ),
      remoteFileStore: fileStore,
      remoteCliDataDir: dataDir,
    );
  }
}
