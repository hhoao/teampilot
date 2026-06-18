import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace_sort.dart';

Workspace _workspace({
  required String id,
  String display = '',
  int updatedAt = 0,
  int createdAt = 0,
}) {
  return Workspace(
    workspaceId: id,
    primaryPath: '/tmp/$id',
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('sortWorkspaces', () {
    test('pins favorites before applying sort mode', () {
      final workspaces = [
        _workspace(id: 'a', display: 'Alpha', updatedAt: 100),
        _workspace(id: 'b', display: 'Beta', updatedAt: 200),
      ];

      final sorted = sortWorkspaces(
        workspaces: workspaces,
        sort: WorkspaceSort.nameAsc,
        favoriteWorkspaceIds: {'a'},
        sessionCountByWorkspaceId: const {},
        displayName: (workspace) => workspace.display,
      );

      expect(sorted.map((p) => p.workspaceId).toList(), ['a', 'b']);
    });

    test('sorts by name ascending', () {
      final workspaces = [
        _workspace(id: 'b', display: 'Beta'),
        _workspace(id: 'a', display: 'Alpha'),
      ];

      final sorted = sortWorkspaces(
        workspaces: workspaces,
        sort: WorkspaceSort.nameAsc,
        favoriteWorkspaceIds: const {},
        sessionCountByWorkspaceId: const {},
        displayName: (workspace) => workspace.display,
        pinFavorites: false,
      );

      expect(sorted.map((p) => p.workspaceId).toList(), ['a', 'b']);
    });

    test('preserves input order when requested', () {
      final workspaces = [
        _workspace(id: 'b', display: 'Beta', updatedAt: 1),
        _workspace(id: 'a', display: 'Alpha', updatedAt: 99),
      ];

      final sorted = sortWorkspaces(
        workspaces: workspaces,
        sort: WorkspaceSort.recentlyUpdated,
        favoriteWorkspaceIds: const {},
        sessionCountByWorkspaceId: const {},
        displayName: (workspace) => workspace.display,
        preserveOrder: true,
      );

      expect(sorted.map((p) => p.workspaceId).toList(), ['b', 'a']);
    });
  });
}
