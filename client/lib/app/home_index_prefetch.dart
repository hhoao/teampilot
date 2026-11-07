import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../services/storage/home_storage.dart';
import '../utils/logging/logger.dart';

/// Warms the on-disk workspace / launch-profile index snapshots as early as
/// [main] allows, so the app repositories' first read hits a warm index file.
///
/// It builds throwaway repositories, so this does **not** populate the
/// app-lifetime repositories' in-memory value caches (Plan 2's `HomeRuntime`
/// warm path owns those). Sequential reads avoid two isolates fighting for
/// cold disk at once.
Future<void> prefetchHomeIndexSnapshots(
  String teampilotRoot,
  HomeStorage storage,
) async {
  final sw = Stopwatch()..start();
  await SessionRepository(
    rootDir: teampilotRoot,
    storage: storage,
  ).loadWorkspacesIndex();
  await LaunchProfileRepository(storage: storage).loadAll();
  appLogger.i('[boot] prefetchHomeIndexSnapshots +${sw.elapsedMilliseconds}ms');
}

/// Future boot may await before dismissing the splash.
///
/// [nativePathPrefetch] is started in `main` against the on-device app-data
/// tree. Remote (SSH / Termux) home must not await it: it is the wrong
/// filesystem, and debug cold-start `Isolate.run` can hang forever — leaving
/// the native splash up.
Future<void> bindHomeIndexPrefetch({
  required bool isRemoteWorkPlane,
  Future<void>? nativePathPrefetch,
  required Future<void> Function() boundHomePrefetch,
}) {
  if (isRemoteWorkPlane) return boundHomePrefetch();
  return nativePathPrefetch ?? boundHomePrefetch();
}
