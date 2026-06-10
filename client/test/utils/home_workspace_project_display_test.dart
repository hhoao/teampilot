import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_project_sort.dart';
import 'package:teampilot/utils/home_workspace_project_display.dart';

void main() {
  AppProject project(String id, {int updatedAt = 0}) => AppProject(
        projectId: id,
        primaryPath: '/tmp/$id',
        createdAt: 1,
        updatedAt: updatedAt,
      );

  AppSession session(String id, String projectId) => AppSession(
        sessionId: id,
        projectId: projectId,
        primaryPath: '/tmp',
        createdAt: 1,
      );

  test('computeHomeWorkspaceProjectDisplay is stable when inputs unchanged', () {
    final projects = [project('a', updatedAt: 2), project('b', updatedAt: 1)];
    final sessions = [session('s1', 'a')];
    const favorites = <String>{};
    const sort = HomeWorkspaceProjectSort.recentlyUpdated;

    final first = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: sessions,
      sort: sort,
      favoriteProjectIds: favorites,
      displayName: (p) => p.projectId,
    );
    final second = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: sessions,
      sort: sort,
      favoriteProjectIds: favorites,
      displayName: (p) => p.projectId,
      cached: first,
      lastProjects: projects,
      lastSessions: sessions,
      lastSort: sort,
      lastFavorites: favorites,
    );

    expect(identical(first.sortedProjects, second.sortedProjects), isTrue);
    expect(identical(first.sessionCounts, second.sessionCounts), isTrue);
    expect(first.sortedProjects.map((p) => p.projectId).toList(), ['a', 'b']);
    expect(first.sessionCounts['a'], 1);
  });

  test('computeHomeWorkspaceProjectDisplay recomputes when sessions change', () {
    final projects = [project('a')];
    const sort = HomeWorkspaceProjectSort.recentlyUpdated;

    final before = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: const [],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );
    final after = computeHomeWorkspaceProjectDisplay(
      projects: projects,
      sessions: [session('s1', 'a')],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );

    expect(identical(before.sessionCounts, after.sessionCounts), isFalse);
    expect(after.sessionCounts['a'], 1);
  });
}
