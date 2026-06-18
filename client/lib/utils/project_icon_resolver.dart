import 'package:flutter/foundation.dart';

import '../models/app_project.dart';
import '../models/project_icon_ref.dart';
import 'project_geometry_catalog.dart';

/// Resolved display target for [ProjectIcon].
@immutable
sealed class ResolvedProjectIcon {
  const ResolvedProjectIcon();
}

@immutable
final class ResolvedProjectGeometryIcon extends ResolvedProjectIcon {
  const ResolvedProjectGeometryIcon(this.assetPath);

  final String assetPath;
}

@immutable
final class ResolvedProjectCustomIcon extends ResolvedProjectIcon {
  const ResolvedProjectCustomIcon(this.relativePath);

  final String relativePath;
}

ResolvedProjectIcon resolveProjectIcon(Workspace project) {
  return switch (project.icon) {
    ProjectIconAuto() => ResolvedProjectGeometryIcon(
      projectGeometryAssetForProjectId(project.projectId),
    ),
    ProjectIconPreset(:final index) => ResolvedProjectGeometryIcon(
      projectGeometryAssetForIndex(index, projectId: project.projectId),
    ),
    ProjectIconCustom(:final relativePath) when relativePath.isNotEmpty =>
      ResolvedProjectCustomIcon(relativePath),
    ProjectIconCustom() => ResolvedProjectGeometryIcon(
      projectGeometryAssetForProjectId(project.projectId),
    ),
  };
}
