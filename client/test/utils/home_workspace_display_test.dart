import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/home_workspace/workspace_sort.dart';
import 'package:teampilot/utils/home_workspace_display.dart';

void main() {
  Workspace workspace(String id, {int updatedAt = 0}) => Workspace(
        workspaceId: id,
        folders: [WorkspaceFolder(path: '/tmp/$id')],
        createdAt: 1,
        updatedAt: updatedAt,
      );

  AppSession session(String id, String workspaceId) => AppSession(
        sessionId: id,
        workspaceId: workspaceId,
        folders: const [WorkspaceFolder(path: '/tmp')],
        createdAt: 1,
      );

  test('computeWorkspaceDisplay is stable when inputs unchanged', () {
    final workspaces = [workspace('a', updatedAt: 2), workspace('b', updatedAt: 1)];
    final sessions = [session('s1', 'a')];
    const favorites = <String>{};
    const sort = WorkspaceSort.recentlyUpdated;

    final first = computeWorkspaceDisplay(
      workspaces: workspaces,
      sessions: sessions,
      sort: sort,
      favoriteWorkspaceIds: favorites,
      displayName: (p) => p.workspaceId,
    );
    final second = computeWorkspaceDisplay(
      workspaces: workspaces,
      sessions: sessions,
      sort: sort,
      favoriteWorkspaceIds: favorites,
      displayName: (p) => p.workspaceId,
      cached: first,
      lastWorkspaces: workspaces,
      lastSessions: sessions,
      lastSort: sort,
      lastFavorites: favorites,
      lastPreserveOrder: false,
    );

    expect(identical(first.sortedWorkspaces, second.sortedWorkspaces), isTrue);
    expect(identical(first.sessionCounts, second.sessionCounts), isTrue);
    expect(first.sortedWorkspaces.map((p) => p.workspaceId).toList(), ['a', 'b']);
    expect(first.sessionCounts['a'], 1);
  });

  test('computeWorkspaceDisplay recomputes when sessions change', () {
    final workspaces = [workspace('a')];
    const sort = WorkspaceSort.recentlyUpdated;

    final before = computeWorkspaceDisplay(
      workspaces: workspaces,
      sessions: const [],
      sort: sort,
      favoriteWorkspaceIds: const {},
      displayName: (p) => p.workspaceId,
    );
    final after = computeWorkspaceDisplay(
      workspaces: workspaces,
      sessions: [session('s1', 'a')],
      sort: sort,
      favoriteWorkspaceIds: const {},
      displayName: (p) => p.workspaceId,
    );

    expect(identical(before.sessionCounts, after.sessionCounts), isFalse);
    expect(after.sessionCounts['a'], 1);
  });

  test('computeWorkspaceDisplay preserves input order when requested', () {
    final workspaces = [
      workspace('b', updatedAt: 1),
      workspace('a', updatedAt: 99),
    ];
    const sort = WorkspaceSort.recentlyUpdated;

    final display = computeWorkspaceDisplay(
      workspaces: workspaces,
      sessions: const [],
      sort: sort,
      favoriteWorkspaceIds: const {},
      displayName: (p) => p.workspaceId,
      preserveOrder: true,
    );

    expect(display.sortedWorkspaces.map((p) => p.workspaceId).toList(), ['b', 'a']);
  });
}
