import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import 'apply_plan_ssh_compiler.dart';
import 'manifest_ssh_flush_plan.dart';
import 'work_path_projector.dart';
import 'work_plane_applier.dart';
import 'work_plane_script_runner.dart';

/// Applies a staged [LaunchManifest] in one batch (local disk or SSH script).
class ManifestExecutor {
  const ManifestExecutor({this.sshClientFactory, this.profileById});

  final SshClientFactory? sshClientFactory;
  final SshProfile? Function(String profileId)? profileById;

  Future<void> flush({
    required LaunchManifest manifest,
    required Filesystem targetFs,
    required Filesystem sourceFs,
    String? sshProfileId,
    String? symlinkProjectionRoot,
    String? homeRoot,
  }) async {
    final runner = SshWorkPlaneScriptRunner.tryCreate(
      sshProfileId: sshProfileId,
      sshClientFactory: sshClientFactory,
      profileById: profileById,
    );
    final workRoot = (symlinkProjectionRoot ?? '').trim();
    final home = (homeRoot ?? workRoot).trim();
    final sameHost = identical(sourceFs, targetFs);
    if (runner != null) {
      if (!sameHost && workRoot.isEmpty) {
        throw StateError(
          'off-home SSH manifest flush requires a non-empty work app-data root',
        );
      }
    }

    final effectiveWorkRoot = workRoot.isNotEmpty ? workRoot : home;
    if (effectiveWorkRoot.isEmpty) {
      throw StateError(
        'manifest flush requires a non-empty work app-data root',
      );
    }
    final built = await buildApplyPlan(
      manifest: manifest,
      sourceFs: sourceFs,
      workFs: targetFs,
      homeRoot: home.isNotEmpty ? home : effectiveWorkRoot,
      workRoot: effectiveWorkRoot,
    );

    if (runner != null) {
      final payload = await compileApplyPlanForSsh(
        plan: built.plan,
        blobs: built.blobs,
      );
      appLogger.d(
        '[session-launch] manifest flush via ssh '
        'ops=${built.plan.ops.length}',
      );
      var scriptEpochs = 0;
      var tarEpochs = 0;
      var stdinBytes = 0;
      if (payload.script case final script?) {
        scriptEpochs = 1;
        stdinBytes += utf8.encode(script).length;
        await runner.runScript(script, operation: 'Launch manifest apply');
      }
      if (payload.gzipTar case final gzipTar?) {
        tarEpochs = 1;
        stdinBytes += gzipTar.length;
        await runner.runStdinCommand(
          command: payload.extractCommand!,
          stdin: gzipTar,
          operation: 'Launch overlay extract',
        );
      }
      appLogger.d(
        '[session-launch] manifest flush via ssh '
        'ops=${built.plan.ops.length} epochs=${scriptEpochs + tarEpochs} '
        'scriptEpochs=$scriptEpochs tarEpochs=$tarEpochs stdinBytes=$stdinBytes',
      );
      return;
    }

    await WorkPlaneApplier(
      fs: targetFs,
      blobs: built.blobs,
      workRoot: effectiveWorkRoot,
    ).apply(built.plan);
  }

  @visibleForTesting
  static String debugBuildApplyScript(LaunchManifest manifest) =>
      buildMutationApplyScript(manifest);
}
