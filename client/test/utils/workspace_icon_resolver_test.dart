import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';
import 'package:teampilot/utils/workspace_geometry_catalog.dart';
import 'package:teampilot/utils/workspace_icon_resolver.dart';

Workspace _workspace({WorkspaceIconRef icon = WorkspaceIconRef.auto}) {
  return Workspace(
    workspaceId: 'workspace-a',
    primaryPath: '/tmp',
    icon: icon,
    createdAt: 0,
  );
}

void main() {
  test('resolveWorkspaceIcon uses auto geometry', () {
    final resolved = resolveWorkspaceIcon(_workspace());
    expect(resolved, isA<ResolvedWorkspaceGeometryIcon>());
    expect(
      (resolved as ResolvedWorkspaceGeometryIcon).assetPath,
      workspaceGeometryAssetForWorkspaceId('workspace-a'),
    );
  });

  test('resolveWorkspaceIcon uses preset geometry', () {
    final resolved = resolveWorkspaceIcon(_workspace(icon: const WorkspaceIconPreset(3)));
    expect(
      (resolved as ResolvedWorkspaceGeometryIcon).assetPath,
      kWorkspaceGeometryIconAssets[3],
    );
  });

  test('resolveWorkspaceIcon uses custom path', () {
    final resolved = resolveWorkspaceIcon(
      _workspace(icon: const WorkspaceIconCustom('icons/workspace-a.png')),
    );
    expect(resolved, isA<ResolvedWorkspaceCustomIcon>());
    expect(
      (resolved as ResolvedWorkspaceCustomIcon).relativePath,
      'icons/workspace-a.png',
    );
  });
}
