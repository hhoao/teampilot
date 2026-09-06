import '../../repositories/ssh_profile_repository.dart';
import '../io/local_filesystem.dart';
import 'app_storage.dart';
import 'targets_repository.dart';
import '../remote_download/remote_download_settings_store.dart';
import '../termux/termux_config_store.dart';

/// Device-local SSH profile catalog.
///
/// Must not ride [AppStorage] home: Android Connect rebinds home onto the
/// remote host, and reading `ssh_profiles/` from that FS empties the catalog,
/// disconnects live pools, then falls home back to local (StartupGate again).
SshProfileRepository deviceLocalSshProfileRepository(String nativeAppDataPath) {
  final paths = AppPaths(nativeAppDataPath);
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return SshProfileRepository(rootDir: paths.sshProfilesDir, fs: fs);
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
