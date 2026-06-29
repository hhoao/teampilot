import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import '../io/sftp_filesystem.dart';
import '../io/wsl_filesystem.dart';
import 'app_storage.dart';
import 'remote_file_store.dart';
import 'runtime_layout.dart';
import 'workspace_layout.dart';

/// Resolved storage backend for business file I/O.
enum StorageBackendMode { native, wsl, ssh }

/// An installed runtime context for a single [RuntimeTarget]: the filesystem,
/// resolved roots, and derived path layouts for that machine. The instance
/// form of the removed global storage singleton — many can coexist
/// (home + per-workspace work planes), held by `RuntimeContextRegistry`.
class RuntimeContext {
  RuntimeContext({
    required this.target,
    required this.filesystem,
    required this.home,
    required this.cwd,
    required this.appDataRoot,
    required this.paths,
  });

  final RuntimeTarget target;
  final Filesystem filesystem;
  final String home;
  final String cwd;
  final String appDataRoot;
  final AppPaths paths;

  /// Resolved backend, derived from the actual filesystem (so an ssh target
  /// that fell back to native reports native, matching legacy semantics).
  StorageBackendMode get mode => filesystem is SftpFilesystem
      ? StorageBackendMode.ssh
      : filesystem is WslFilesystem
      ? StorageBackendMode.wsl
      : StorageBackendMode.native;

  /// POSIX separators for the *resolved* backend (wsl/ssh).
  bool get usesPosixPaths => mode != StorageBackendMode.native;

  bool get storageIsRemote => filesystem is SftpFilesystem;

  /// Workbench path layout under `{appDataRoot}/workspace/` (was on
  /// StorageRootsSnapshot, now derived here).
  late final WorkspaceLayout workspace = WorkspaceLayout(
    teampilotRoot: appDataRoot,
    fs: filesystem,
  );

  /// CLI runtime layout: cli-defaults/, identities-runtime/, session runtime.
  late final RuntimeLayout layout = RuntimeLayout(
    teampilotRoot: appDataRoot,
    fs: filesystem,
    workspace: workspace,
  );

  // ---- Derived control-plane paths (absorbed from StorageRootsSnapshot) ----

  /// Alias for [filesystem].
  Filesystem get fs => filesystem;

  /// Alias for [appDataRoot] (the TeamPilot app-data root for this context).
  String get teampilotRoot => appDataRoot;

  RemoteFileStore? get remoteFileStore =>
      filesystem is SftpFilesystem ? (filesystem as SftpFilesystem).store : null;

  String get launchProfilesDir =>
      AppPaths.launchProfilesDirForTeampilotRoot(appDataRoot);
  String get skillsRoot => AppPaths.skillsDirForTeampilotRoot(appDataRoot);
  String get skillBackupsDir =>
      AppPaths.skillBackupsDirForTeampilotRoot(appDataRoot);
  String get workspaceDir =>
      AppPaths.workspaceDirForTeampilotRoot(appDataRoot);
  String get skillReposConfigPath =>
      AppPaths.skillReposConfigPathForTeampilotRoot(appDataRoot);
  String get pluginsRoot => AppPaths.pluginsDirForTeampilotRoot(appDataRoot);
  String get pluginBackupsDir =>
      AppPaths.pluginBackupsDirForTeampilotRoot(appDataRoot);
  String get pluginsJsonPath =>
      AppPaths.pluginsJsonForTeampilotRoot(appDataRoot);
  String get pluginMarketplacesConfigPath =>
      AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(appDataRoot);
  String get pluginMarketplaceCacheDir =>
      AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(appDataRoot);
  String get pluginExternalCacheDir =>
      AppPaths.pluginExternalCacheDirForTeampilotRoot(appDataRoot);
  String get mcpServersJsonPath =>
      AppPaths.mcpServersJsonForTeampilotRoot(appDataRoot);
  String get mcpRegistrySourcesConfigPath =>
      AppPaths.mcpRegistrySourcesConfigPathForTeampilotRoot(appDataRoot);
  String get mcpDiscoveryCacheDir =>
      AppPaths.mcpDiscoveryCacheDirForTeampilotRoot(appDataRoot);
}
