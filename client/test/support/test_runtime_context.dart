import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
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

/// Binds a native home [RuntimeContext] rooted at [dir] for tests (replaces the
/// removed `RuntimeStorageContext.install`).
void bindTestNativeHome(String dir) {
  AppStorage.installForTesting(
    filesystem: LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(dir),
    ),
    paths: AppPaths(dir),
    home: dir,
    cwd: dir,
  );
}
