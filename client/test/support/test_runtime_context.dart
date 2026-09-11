import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

/// A native (local) [RuntimeContext] rooted at [dir] — derives all control-plane
/// paths from [dir]. Replaces the removed StorageRootsSnapshot test fakes.
RuntimeContext testRuntimeContext(String dir) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(dir),
  ),
  home: dir,
  cwd: dir,
  appDataRoot: dir,
  paths: AppPaths(dir),
);

/// Shared test home storage owned by the test support layer (replaces the
/// deleted `AppStorage.installForTesting` global). Installed by
/// [bindTestNativeHome], [installTestHomeStorage], or `setUpTestAppStorage`.
HomeStorage? _testHome;

/// Whether a shared test home is installed (lets helpers auto-install a
/// fallback instead of throwing).
bool get testHomeStorageInstalled => _testHome != null;

/// The shared test home storage installed by [bindTestNativeHome] /
/// [installTestHomeStorage] / `setUpTestAppStorage`. Pass into
/// constructor-injected repositories/cubits. Throws when no test home was
/// installed in this test.
HomeStorage get testHomeStorage =>
    _testHome ??
    (throw StateError(
      'No test home storage installed; call setUpTestAppStorage(), '
      'bindTestNativeHome(), or installTestHomeStorage() first.',
    ));

/// Builds a fresh [HomeStorage] over the current shared test home context.
/// For tests needing their own instance (independent generations).
HomeStorage buildTestHomeStorage() => HomeStorage(testHomeStorage.context);

/// Binds a native home [RuntimeContext] rooted at [dir] as the shared test
/// home (replaces the removed `RuntimeStorageContext.install`). Returns the
/// [HomeStorage] over the freshly bound context for constructor injection;
/// re-binding swaps the shared context so lazily-reading consumers follow.
HomeStorage bindTestNativeHome(String dir) {
  final storage = HomeStorage(testRuntimeContext(dir));
  _testHome = storage;
  AppPathsBootstrapper.syncPaths(AppPaths(dir));
  return storage;
}

/// Test seam replacing the deleted `AppStorage.installForTesting`: installs a
/// native home context rooted at [paths] over [filesystem] as the shared test
/// home storage and syncs [AppPathsBootstrapper].
HomeStorage installTestHomeStorage({
  required Filesystem filesystem,
  required AppPaths paths,
  String home = '/home/test',
  String cwd = '/home/test',
}) {
  final storage = HomeStorage(
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: filesystem,
      home: home,
      cwd: cwd,
      appDataRoot: paths.basePath,
      paths: paths,
    ),
  );
  _testHome = storage;
  AppPathsBootstrapper.syncPaths(paths);
  return storage;
}

/// Test seam replacing the deleted `AppStorage.resetForTesting`.
void resetTestHomeStorage() {
  _testHome = null;
}
