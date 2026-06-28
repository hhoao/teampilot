import '../repositories/launch_profile_repository.dart';
import '../repositories/session_repository.dart';
import '../utils/logger.dart';

/// Warms workspace / launch-profile index caches as early as [main] allows.
///
/// Sequential reads avoid two isolates fighting for cold disk at once.
Future<void> prefetchHomeIndexSnapshots(String teampilotRoot) async {
  final sw = Stopwatch()..start();
  await SessionRepository(rootDir: teampilotRoot).loadWorkspacesIndex();
  await LaunchProfileRepository().loadAll();
  appLogger.i(
    '[boot] prefetchHomeIndexSnapshots +${sw.elapsedMilliseconds}ms',
  );
}
