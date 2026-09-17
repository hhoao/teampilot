import 'package:teampilot_apply/teampilot_apply.dart';
import 'package:teampilot_fs/teampilot_fs.dart';

import 'launch_manifest.dart';
import 'resource_contributor.dart';
import 'session_cli_plugin.dart';
import 'session_init_exception.dart';
import 'session_init_request.dart';
import 'session_init_result.dart';
import 'session_layout.dart';
import 'work_path_projector.dart';

final class SessionScheduler {
  const SessionScheduler();

  Future<SessionInitResult> init({
    required SessionInitRequest request,
    required Filesystem homeFs,
    required Filesystem workFs,
    required SessionCliPlugin plugin,
    List<ResourceContributor> resources = const [],
  }) async {
    final env = <String, String>{};

    final layout = await _stage(SessionInitStage.layout, () async {
      if (plugin.toolId != request.cli) {
        throw SessionInitException(
          SessionInitStage.layout,
          message: 'plugin/tool mismatch',
        );
      }
      return SessionLayout(
        teampilotRoot: request.workRoot,
        pathContext: workFs.pathContext,
      );
    });

    final manifest = await _stage(SessionInitStage.contribute, () async {
      final next = LaunchManifest(pathContext: workFs.pathContext);
      for (final resource in resources) {
        await resource.contribute(
          request: request,
          layout: layout,
          homeFs: homeFs,
          manifest: next,
        );
      }
      await plugin.contribute(
        request: request,
        layout: layout,
        homeFs: homeFs,
        workFs: workFs,
        manifest: next,
      );
      return next;
    });

    final built = await _stage(SessionInitStage.project, () {
      return buildApplyPlan(
        manifest: manifest,
        sourceFs: homeFs,
        workFs: workFs,
        homeRoot: request.homeRoot,
        workRoot: request.workRoot,
      );
    });

    await _stage(SessionInitStage.apply, () {
      return WorkPlaneApplier(
        fs: workFs,
        blobs: built.blobs,
        workRoot: request.workRoot,
      ).apply(built.plan);
    });

    await _stage(SessionInitStage.afterApply, () {
      return plugin.afterApply(
        workFs: workFs,
        layout: layout,
        environment: env,
      );
    });

    return _stage(SessionInitStage.spawn, () async {
      final spec = plugin.buildSpawn(
        request: request,
        layout: layout,
        environment: env,
      );
      return SessionInitResult(spawn: spec);
    });
  }

  Future<T> _stage<T>(SessionInitStage stage, Future<T> Function() body) async {
    try {
      return await body();
    } on SessionInitException {
      rethrow;
    } on Object catch (e) {
      throw SessionInitException(stage, cause: e);
    }
  }
}
