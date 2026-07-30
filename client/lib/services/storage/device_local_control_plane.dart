import '../../repositories/ssh_profile_repository.dart';
import '../io/local_filesystem.dart';
import 'app_storage.dart';
import 'targets_repository.dart';

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
