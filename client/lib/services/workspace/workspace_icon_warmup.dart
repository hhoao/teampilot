import 'dart:math' show min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

import '../../models/workspace.dart';
import '../../utils/workspace_geometry_catalog.dart';
import '../../utils/workspace_icon_resolver.dart';
import '../../utils/yield_ui_frame.dart';
import '../storage/app_storage.dart';
import '../storage/workspace_layout.dart';
import 'workspace_icon_service.dart';
import 'workspace_icon_storage.dart';

/// Parses bundled geometry SVGs and custom workspace icons during bootstrap so
/// the home grid does not paint empty avatar boxes on first entry.
abstract final class WorkspaceIconWarmup {
  WorkspaceIconWarmup._();

  static const _geometryBatchSize = 4;

  static Future<void> warm(List<Workspace> workspaces) async {
    final assets = kWorkspaceGeometryIconAssets;
    for (var i = 0; i < assets.length; i += _geometryBatchSize) {
      final end = min(i + _geometryBatchSize, assets.length);
      await Future.wait([
        for (var j = i; j < end; j++) _warmGeometryAsset(assets[j]),
      ]);
      await yieldUiFrame();
    }

    var customCount = 0;
    for (final workspace in workspaces) {
      if (await _warmCustomIcon(workspace)) {
        customCount++;
        if (customCount.isOdd) {
          await yieldUiFrame();
        }
      }
    }
  }

  /// Bytes cache plus full vector decode so embedded raster data lands in
  /// [imageCache] before the workspace grid mounts.
  static Future<void> _warmGeometryAsset(String assetPath) async {
    final loader = SvgAssetLoader(assetPath);
    await svg.cache.putIfAbsent(
      loader.cacheKey(null),
      () => loader.loadBytes(null),
    );
    final info = await vg.loadPicture(loader, null);
    info.picture.dispose();
  }

  static Future<bool> _warmCustomIcon(Workspace workspace) async {
    final resolved = resolveWorkspaceIcon(workspace);
    if (resolved is! ResolvedWorkspaceCustomIcon) return false;
    final relativePath = resolved.relativePath;
    if (relativePath.isEmpty) return false;

    final bytes = await workspaceIconService.loadCustomBytes(
      workspaceDir: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath)
          .workspaceDir(workspace.workspaceId),
      relativePath: relativePath,
    );
    if (bytes == null || bytes.isEmpty) return false;

    if (WorkspaceIconStorage.isSvgPath(relativePath)) {
      final loader = SvgBytesLoader(Uint8List.fromList(bytes));
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
      final info = await vg.loadPicture(loader, null);
      info.picture.dispose();
    } else {
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      codec.dispose();
    }
    return true;
  }
}
