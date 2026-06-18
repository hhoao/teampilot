import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_project_sort.dart';
import 'package:teampilot/utils/home_workspace_project_display.dart';

void main() {
  Workspace project(String id, {int updatedAt = 0}) => Workspace(
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

  test('computeWorkspaceDisplay is stable when inputs unchanged', () {
    final projects = [project('a', updatedAt: 2), project('b', updatedAt: 1)];
    final sessions = [session('s1', 'a')];
    const favorites = <String>{};
    const sort = WorkspaceSort.recentlyUpdated;

    final first = computeWorkspaceDisplay(
      projects: projects,
      sessions: sessions,
      sort: sort,
      favoriteProjectIds: favorites,
      displayName: (p) => p.projectId,
    );
    final second = computeWorkspaceDisplay(
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
      lastPreserveOrder: false,
    );

    expect(identical(first.sortedProjects, second.sortedProjects), isTrue);
    expect(identical(first.sessionCounts, second.sessionCounts), isTrue);
    expect(first.sortedProjects.map((p) => p.projectId).toList(), ['a', 'b']);
    expect(first.sessionCounts['a'], 1);
  });

  test('computeWorkspaceDisplay recomputes when sessions change', () {
    final projects = [project('a')];
    const sort = WorkspaceSort.recentlyUpdated;

    final before = computeWorkspaceDisplay(
      projects: projects,
      sessions: const [],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );
    final after = computeWorkspaceDisplay(
      projects: projects,
      sessions: [session('s1', 'a')],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
    );

    expect(identical(before.sessionCounts, after.sessionCounts), isFalse);
    expect(after.sessionCounts['a'], 1);
  });

  test('computeWorkspaceDisplay preserves input order when requested', () {
    final projects = [
      project('b', updatedAt: 1),
      project('a', updatedAt: 99),
    ];
    const sort = WorkspaceSort.recentlyUpdated;

    final display = computeWorkspaceDisplay(
      projects: projects,
      sessions: const [],
      sort: sort,
      favoriteProjectIds: const {},
      displayName: (p) => p.projectId,
      preserveOrder: true,
    );

    expect(display.sortedProjects.map((p) => p.projectId).toList(), ['b', 'a']);
  });
}
