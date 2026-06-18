import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/project_icon_ref.dart';
import 'package:teampilot/utils/project_geometry_catalog.dart';
import 'package:teampilot/utils/project_icon_resolver.dart';

Workspace _project({ProjectIconRef icon = ProjectIconRef.auto}) {
  return Workspace(
    projectId: 'project-a',
    primaryPath: '/tmp',
    icon: icon,
    createdAt: 0,
  );
}

void main() {
  test('resolveProjectIcon uses auto geometry', () {
    final resolved = resolveProjectIcon(_project());
    expect(resolved, isA<ResolvedProjectGeometryIcon>());
    expect(
      (resolved as ResolvedProjectGeometryIcon).assetPath,
      projectGeometryAssetForProjectId('project-a'),
    );
  });

  test('resolveProjectIcon uses preset geometry', () {
    final resolved = resolveProjectIcon(_project(icon: const ProjectIconPreset(3)));
    expect(
      (resolved as ResolvedProjectGeometryIcon).assetPath,
      kProjectGeometryIconAssets[3],
    );
  });

  test('resolveProjectIcon uses custom path', () {
    final resolved = resolveProjectIcon(
      _project(icon: const ProjectIconCustom('icons/project-a.png')),
    );
    expect(resolved, isA<ResolvedProjectCustomIcon>());
    expect(
      (resolved as ResolvedProjectCustomIcon).relativePath,
      'icons/project-a.png',
    );
  });
}
