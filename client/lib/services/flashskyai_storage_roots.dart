import '../models/ssh_profile.dart';
import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'io/filesystem.dart';
import 'io/sftp_filesystem.dart';
import 'remote_file_store.dart';
import 'runtime_storage_context.dart';

/// Resolved filesystem roots for teams, skills, sessions, and CLI config profiles.
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
  }) : fs = fs ?? AppStorage.fs,
       layout =
           layout ??
           CliDataLayout(
             teampilotRoot: teampilotRoot,
             fs: fs ?? AppStorage.fs,
           );

  factory StorageRootsSnapshot.fromContext(RuntimeStorageContext context) {
    final root = context.appDataRoot;
    final fs = context.filesystem;
    final layout = CliDataLayout(teampilotRoot: root, fs: fs);
    return StorageRootsSnapshot(
      teampilotRoot: root,
      fs: fs,
      layout: layout,
      teamsUiDir: AppPaths.teamsUiDirForTeampilotRoot(root),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(root),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(root),
      appProjectsDir: AppPaths.appProjectsDirForTeampilotRoot(root),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(root),
    );
  }

  /// UI app-data root: [AppStorage.appDataRoot] locally; remote XDG app dir on SSH.
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
    Future<RuntimeStorageContext> Function()? reinstallContext,
  }) : _isSshMode = isSshMode,
       _sshProfileResolver = sshProfileResolver,
       _reinstallContext = reinstallContext;

  final bool Function()? _isSshMode;
  final SshProfile? Function()? _sshProfileResolver;
  final Future<RuntimeStorageContext> Function()? _reinstallContext;

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
    final reinstall = _reinstallContext;
    if (reinstall != null &&
        ((_isSshMode?.call() ?? false) || _sshProfileResolver?.call() != null)) {
      await reinstall();
    }
    return StorageRootsSnapshot.fromContext(RuntimeStorageContext.current);
  }
}
