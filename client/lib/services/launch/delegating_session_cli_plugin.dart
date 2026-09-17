import 'package:teampilot_fs/teampilot_fs.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart'
    show
        LaunchManifest,
        SessionCliPlugin,
        SessionInitRequest,
        SessionLayout,
        SessionSpawnSpec;

final class DelegatingSessionCliPlugin implements SessionCliPlugin {
  DelegatingSessionCliPlugin({
    required this.toolId,
    required this.onContribute,
    required this.onSessionConfigDir,
    required this.onAfterApply,
    required this.onBuildSpawn,
  });

  @override
  final String toolId;

  final Future<void> Function({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  })
  onContribute;

  final String Function(SessionLayout layout, SessionInitRequest request)
  onSessionConfigDir;

  final Future<void> Function({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  })
  onAfterApply;

  final SessionSpawnSpec Function({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  })
  onBuildSpawn;

  @override
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  }) {
    return onContribute(
      request: request,
      layout: layout,
      homeFs: homeFs,
      workFs: workFs,
      manifest: manifest,
    );
  }

  @override
  String sessionConfigDir(SessionLayout layout, SessionInitRequest request) {
    return onSessionConfigDir(layout, request);
  }

  @override
  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) {
    return onAfterApply(
      workFs: workFs,
      layout: layout,
      environment: environment,
    );
  }

  @override
  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  }) {
    return onBuildSpawn(
      request: request,
      layout: layout,
      environment: environment,
    );
  }
}
