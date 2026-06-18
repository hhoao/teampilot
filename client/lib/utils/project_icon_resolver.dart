import 'package:flutter/foundation.dart';

import '../models/app_workspace.dart';
import '../models/workspace_icon_ref.dart';
import 'workspace_geometry_catalog.dart';

/// Resolved display target for [WorkspaceIcon].
@immutable
sealed class ResolvedWorkspaceIcon {
  const ResolvedWorkspaceIcon();
}

@immutable
final class ResolvedWorkspaceGeometryIcon extends ResolvedWorkspaceIcon {
  const ResolvedWorkspaceGeometryIcon(this.assetPath);

  final String assetPath;
}

@immutable
final class ResolvedWorkspaceCustomIcon extends ResolvedWorkspaceIcon {
  const ResolvedWorkspaceCustomIcon(this.relativePath);

  final String relativePath;
}

ResolvedWorkspaceIcon resolveWorkspaceIcon(Workspace workspace) {
  return switch (workspace.icon) {
    WorkspaceIconAuto() => ResolvedWorkspaceGeometryIcon(
      workspaceGeometryAssetForWorkspaceId(workspace.workspaceId),
    ),
    WorkspaceIconPreset(:final index) => ResolvedWorkspaceGeometryIcon(
      workspaceGeometryAssetForIndex(index, workspaceId: workspace.workspaceId),
    ),
    WorkspaceIconCustom(:final relativePath) when relativePath.isNotEmpty =>
      ResolvedWorkspaceCustomIcon(relativePath),
    WorkspaceIconCustom() => ResolvedWorkspaceGeometryIcon(
      workspaceGeometryAssetForWorkspaceId(workspace.workspaceId),
    ),
  };
}
