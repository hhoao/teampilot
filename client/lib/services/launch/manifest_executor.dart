import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import 'apply_plan.dart';
import 'manifest_ssh_flush_plan.dart';
import 'work_path_projector.dart';
import 'work_plane_applier.dart';

/// Applies a staged [LaunchManifest] onto [targetFs] via [WorkPlaneApplier].
class ManifestExecutor {
  const ManifestExecutor({this.sshClientFactory, this.profileById});

  /// SSH factory used by session after-apply adapters, not by [flush].
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
    final workRoot = (symlinkProjectionRoot ?? '').trim();
    final home = (homeRoot ?? workRoot).trim();
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
    var blobCount = 0;
    var blobBytes = 0;
    var inlineBytes = 0;
    for (final op in built.plan.ops) {
      switch (op) {
        case ApplyWriteBlob(:final sha256):
          blobCount += 1;
          blobBytes += (await built.blobs.open(sha256)).length;
        case ApplyTree(:final entries):
          blobCount += entries.length;
          for (final entry in entries) {
            blobBytes += (await built.blobs.open(entry.sha256)).length;
          }
        case ApplyWriteInline(:final content):
          inlineBytes += utf8.encode(content).length;
        default:
          break;
      }
    }
    appLogger.d(
      '[session-launch] apply-plan protocol=${built.plan.protocolVersion} '
      'ops=${built.plan.ops.length} provided=${built.providedLinks} '
      'blobs=$blobCount blobBytes=$blobBytes inlineBytes=$inlineBytes',
    );

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
