import 'dart:math' show min;

import 'package:flutter_svg/flutter_svg.dart';

import '../../models/workspace.dart';
import '../../utils/workspace_geometry_catalog.dart';
import '../../utils/workspace_icon_resolver.dart';
import '../../utils/yield_ui_frame.dart';
import '../storage/app_storage.dart';
import '../storage/workspace_layout.dart';
import 'workspace_icon_service.dart';

/// Parses bundled geometry SVGs and custom workspace icons during bootstrap so
/// the home grid does not paint empty avatar boxes on first entry.
abstract final class WorkspaceIconWarmup {
  WorkspaceIconWarmup._();

  static const _geometryBatchSize = 8;

  static Future<void> warm(List<Workspace> workspaces) async {
    final assets = kWorkspaceGeometryIconAssets;
    for (var i = 0; i < assets.length; i += _geometryBatchSize) {
      final end = min(i + _geometryBatchSize, assets.length);
      await Future.wait([
        for (var j = i; j < end; j++) _cacheGeometrySvg(assets[j]),
      ]);
      await yieldUiFrame();
    }

    var customCount = 0;
    for (final workspace in workspaces) {
      if (await _cacheCustomIcon(workspace)) {
        customCount++;
        if (customCount.isOdd) {
          await yieldUiFrame();
        }
      }
    }
  }

  static Future<void> _cacheGeometrySvg(String assetPath) async {
    final loader = SvgAssetLoader(assetPath);
    await svg.cache.putIfAbsent(
      loader.cacheKey(null),
      () => loader.loadBytes(null),
    );
  }

  static Future<bool> _cacheCustomIcon(Workspace workspace) async {
    final resolved = resolveWorkspaceIcon(workspace);
    if (resolved is! ResolvedWorkspaceCustomIcon) return false;
    final relativePath = resolved.relativePath;
    if (relativePath.isEmpty) return false;

    await workspaceIconService.loadCustomBytes(
      workspaceDir: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath)
          .workspaceDir(workspace.workspaceId),
      relativePath: relativePath,
    );
    return true;
  }
}
