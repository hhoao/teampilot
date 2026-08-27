import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../utils/logging/logger.dart';

/// Warms workspace / launch-profile index caches as early as [main] allows.
///
/// Sequential reads avoid two isolates fighting for cold disk at once.
Future<void> prefetchHomeIndexSnapshots(String teampilotRoot) async {
  final sw = Stopwatch()..start();
  await SessionRepository(rootDir: teampilotRoot).loadWorkspacesIndex();
  await LaunchProfileRepository().loadAll();
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
