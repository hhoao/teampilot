import '../../models/ssh_profile.dart';
import 'app_storage.dart';
import 'runtime_layout.dart';
import 'workspace_layout.dart';
import '../io/filesystem.dart';
import '../io/sftp_filesystem.dart';
import 'remote_file_store.dart';
import 'runtime_storage_context.dart';

/// Resolved filesystem roots for teams, skills, sessions, and CLI config profiles.
class StorageRootsSnapshot {
  StorageRootsSnapshot({
    bool? storageIsRemote,
    required this.teampilotRoot,
    Filesystem? fs,
    RuntimeLayout? layout,
    WorkspaceLayout? workspace,
    required this.identitiesUiDir,
    required this.skillsRoot,
    required this.skillBackupsDir,
    required this.workspaceDir,
    required this.skillReposConfigPath,
    required this.pluginsRoot,
    required this.pluginBackupsDir,
    required this.pluginsJsonPath,
    required this.pluginMarketplacesConfigPath,
    required this.pluginMarketplaceCacheDir,
    required this.pluginExternalCacheDir,
    required this.mcpServersJsonPath,
    required this.mcpRegistrySourcesConfigPath,
  }) : fs = fs ?? AppStorage.fs,
       workspace =
           workspace ??
           WorkspaceLayout(teampilotRoot: teampilotRoot, fs: fs ?? AppStorage.fs),
       layout =
           layout ??
           RuntimeLayout(
             teampilotRoot: teampilotRoot,
             fs: fs ?? AppStorage.fs,
             workspace: workspace,
           );

  factory StorageRootsSnapshot.fromContext(RuntimeStorageContext context) {
    final root = context.appDataRoot;
    final fs = context.filesystem;
    final workspace = WorkspaceLayout(teampilotRoot: root, fs: fs);
    final layout = RuntimeLayout(
      teampilotRoot: root,
      fs: fs,
      workspace: workspace,
    );
    return StorageRootsSnapshot(
      teampilotRoot: root,
      fs: fs,
      layout: layout,
      workspace: workspace,
      identitiesUiDir: AppPaths.identitiesUiDirForTeampilotRoot(root),
      skillsRoot: AppPaths.skillsDirForTeampilotRoot(root),
      skillBackupsDir: AppPaths.skillBackupsDirForTeampilotRoot(root),
      workspaceDir: AppPaths.workspaceDirForTeampilotRoot(root),
      skillReposConfigPath: AppPaths.skillReposConfigPathForTeampilotRoot(root),
      pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(root),
      pluginBackupsDir: AppPaths.pluginBackupsDirForTeampilotRoot(root),
      pluginsJsonPath: AppPaths.pluginsJsonForTeampilotRoot(root),
      pluginMarketplacesConfigPath:
          AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(root),
      pluginMarketplaceCacheDir:
          AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(root),
      pluginExternalCacheDir: AppPaths.pluginExternalCacheDirForTeampilotRoot(
        root,
      ),
      mcpServersJsonPath: AppPaths.mcpServersJsonForTeampilotRoot(root),
      mcpRegistrySourcesConfigPath:
          AppPaths.mcpRegistrySourcesConfigPathForTeampilotRoot(root),
    );
  }

  /// UI app-data root: [AppStorage.appDataRoot] locally; remote XDG app dir on SSH.
  final String teampilotRoot;
  final Filesystem fs;

  final String identitiesUiDir;
  final String skillsRoot;
  final String skillBackupsDir;

  /// `workspace/projects/` — per-project manifest, profile, sessions, bus.
  final String workspaceDir;

  /// Skill marketplace repo list (`skills/repos.json`).
  final String skillReposConfigPath;

  final String pluginsRoot;
  final String pluginBackupsDir;
  final String pluginsJsonPath;
  final String pluginMarketplacesConfigPath;
  final String pluginMarketplaceCacheDir;
  final String pluginExternalCacheDir;

  /// Global MCP catalog (`mcp/mcp_servers.json`).
  final String mcpServersJsonPath;

  /// Remote registry API sources (`mcp/registry_sources.json`).
  final String mcpRegistrySourcesConfigPath;

  /// Workbench path layout under `{teampilotRoot}/workspace/`.
  final WorkspaceLayout workspace;

  /// CLI runtime layout: `cli-defaults/`, `identities-runtime/`, session runtime dirs.
  final RuntimeLayout layout;

  bool get storageIsRemote => fs is SftpFilesystem;
  RemoteFileStore? get remoteFileStore =>
      fs is SftpFilesystem ? (fs as SftpFilesystem).store : null;
}

class StorageRoots {
  StorageRoots({
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

  /// Re-runs [reinstallContext] then resolves a fresh snapshot (storage backend changes).
  Future<StorageRootsSnapshot> reinstallAndResolve() async {
    final reinstall = _reinstallContext;
    if (reinstall != null) {
      await reinstall();
    }
    invalidate();
    return resolve(forceRefresh: true);
  }

  Future<StorageRootsSnapshot> _resolveUncached() async {
    final reinstall = _reinstallContext;
    if (reinstall != null &&
        ((_isSshMode?.call() ?? false) ||
            _sshProfileResolver?.call() != null)) {
      await reinstall();
    }
    return StorageRootsSnapshot.fromContext(RuntimeStorageContext.current);
  }
}
