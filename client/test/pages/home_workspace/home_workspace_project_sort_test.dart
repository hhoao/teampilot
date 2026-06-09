import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_project_sort.dart';

AppProject _project({
  required String id,
  String display = '',
  int updatedAt = 0,
  int createdAt = 0,
}) {
  return AppProject(
    projectId: id,
    primaryPath: '/tmp/$id',
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  group('sortHomeWorkspaceProjects', () {
    test('pins favorites before applying sort mode', () {
      final projects = [
        _project(id: 'a', display: 'Alpha', updatedAt: 100),
        _project(id: 'b', display: 'Beta', updatedAt: 200),
      ];

      final sorted = sortHomeWorkspaceProjects(
        projects: projects,
        sort: HomeWorkspaceProjectSort.nameAsc,
        favoriteProjectIds: {'a'},
        sessionCountByProjectId: const {},
        displayName: (project) => project.display,
      );

      expect(sorted.map((p) => p.projectId).toList(), ['a', 'b']);
    });

    test('sorts by name ascending', () {
      final projects = [
        _project(id: 'b', display: 'Beta'),
        _project(id: 'a', display: 'Alpha'),
      ];

      final sorted = sortHomeWorkspaceProjects(
        projects: projects,
        sort: HomeWorkspaceProjectSort.nameAsc,
        favoriteProjectIds: const {},
        sessionCountByProjectId: const {},
        displayName: (project) => project.display,
        pinFavorites: false,
      );

      expect(sorted.map((p) => p.projectId).toList(), ['a', 'b']);
    });

    test('preserves input order when requested', () {
      final projects = [
        _project(id: 'b', display: 'Beta', updatedAt: 1),
        _project(id: 'a', display: 'Alpha', updatedAt: 99),
      ];

      final sorted = sortHomeWorkspaceProjects(
        projects: projects,
        sort: HomeWorkspaceProjectSort.recentlyUpdated,
        favoriteProjectIds: const {},
        sessionCountByProjectId: const {},
        displayName: (project) => project.display,
        preserveOrder: true,
      );

      expect(sorted.map((p) => p.projectId).toList(), ['b', 'a']);
    });
  });
}
