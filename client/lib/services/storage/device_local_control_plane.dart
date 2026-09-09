import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../cli/remote_cli_path_cache.dart';
import '../io/local_filesystem.dart';
import 'app_paths.dart';
import 'home_storage.dart';
import 'runtime_context.dart';
import 'targets_repository.dart';
import '../remote_download/remote_download_settings_store.dart';
import '../termux/termux_config_store.dart';

/// Device-local SSH profile catalog.
///
/// Must not ride the app-scoped home plane: Android Connect rebinds home onto
/// the remote host, and reading `ssh_profiles/` from that FS empties the
/// catalog, disconnects live pools, then falls home back to local (StartupGate
/// again). The repository's [HomeStorage] is therefore a device-local context
/// over [nativeAppDataPath] — its `rootDir`/`fs` overrides keep every read and
/// write pinned here even when the app-scoped home swaps.
SshProfileRepository deviceLocalSshProfileRepository(String nativeAppDataPath) {
  final paths = AppPaths(nativeAppDataPath);
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return SshProfileRepository(
    rootDir: paths.sshProfilesDir,
    fs: fs,
    storage: HomeStorage(
      RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: nativeAppDataPath,
        cwd: nativeAppDataPath,
        appDataRoot: nativeAppDataPath,
        paths: paths,
      ),
    ),
  );
}

/// Device-local `targets.json` (same control-plane pin as SSH profiles).
TargetsRepository deviceLocalTargetsRepository(String nativeAppDataPath) {
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return TargetsRepository(rootDir: nativeAppDataPath, fs: fs);
}

/// Device-local Termux loopback config (`.termux/config.json` under native app data).
TermuxConfigStore deviceLocalTermuxConfigStore(String nativeAppDataPath) {
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return TermuxConfigStore(rootDir: nativeAppDataPath, fs: fs);
}

/// Native home storage over [nativeAppDataPath] for boot-time prefetches that
/// must run before the app-scoped home plane is bound.
HomeStorage deviceLocalHomeStorage(String nativeAppDataPath) {
  final paths = AppPaths(nativeAppDataPath);
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return HomeStorage(
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: nativeAppDataPath,
      cwd: nativeAppDataPath,
      appDataRoot: nativeAppDataPath,
      paths: paths,
    ),
  );
}

/// Device-local remote download catalog overrides (`.remote-download/` under native app data).
RemoteDownloadSettingsStore deviceLocalRemoteDownloadSettingsStore(
  String nativeAppDataPath,
) {
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return RemoteDownloadSettingsStore(rootDir: nativeAppDataPath, fs: fs);
}

/// Device-local registry catalog cache root (`catalog-cache/` under native
/// app data).
///
/// Catalog caches must be device-local: on Android the home root is remote
/// (SFTP), so a cache under it costs a network round trip per read —
/// defeating itself.
String deviceLocalCatalogCacheRoot(String nativeAppDataPath) =>
    AppPaths.pathContextForDataRoot(nativeAppDataPath)
        .join(nativeAppDataPath, 'catalog-cache');

/// Device-local `LocalFilesystem` pinned to the native app-data path context.
LocalFilesystem deviceLocalCatalogCacheFilesystem(String nativeAppDataPath) =>
    LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
    );

/// Device-local remote CLI path cache (`remote-cli-paths.json` under native
/// app data) — same control-plane pin as SSH profiles: discovery applies
/// instantly on boot instead of blocking on SSH probe loops, and reads never
/// hit the possibly-remote home filesystem.
RemoteCliPathCache deviceLocalRemoteCliPathCache(String nativeAppDataPath) =>
    RemoteCliPathCache(
      fs: deviceLocalCatalogCacheFilesystem(nativeAppDataPath),
      filePath: AppPaths.pathContextForDataRoot(nativeAppDataPath).join(
        nativeAppDataPath,
        'remote-cli-paths.json',
      ),
    );
