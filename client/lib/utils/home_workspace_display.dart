import '../models/workspace.dart';
import '../models/app_session.dart';
import '../pages/home_workspace/workspace_sort.dart';

class WorkspaceDisplay {
  const WorkspaceDisplay({
    required this.sortedWorkspaces,
    required this.sessionCounts,
  });

  final List<Workspace> sortedWorkspaces;
  final Map<String, int> sessionCounts;
}

/// Sorts [workspaces] and counts sessions. Returns the previous [cached] result
/// when all inputs are unchanged (reference equality on lists/maps).
WorkspaceDisplay computeWorkspaceDisplay({
  required List<Workspace> workspaces,
  required List<AppSession> sessions,
  required WorkspaceSort sort,
  required Set<String> favoriteWorkspaceIds,
  required String Function(Workspace workspace) displayName,
  bool preserveOrder = false,
  WorkspaceDisplay? cached,
  List<Workspace>? lastWorkspaces,
  List<AppSession>? lastSessions,
  WorkspaceSort? lastSort,
  Set<String>? lastFavorites,
  bool? lastPreserveOrder,
}) {
  if (cached != null &&
      identical(workspaces, lastWorkspaces) &&
      identical(sessions, lastSessions) &&
      sort == lastSort &&
      identical(favoriteWorkspaceIds, lastFavorites) &&
      preserveOrder == lastPreserveOrder) {
    return cached;
  }

  final sessionCounts = homeWorkspaceSessionCountByWorkspaceId(sessions);
  final sortedWorkspaces = sortWorkspaces(
    workspaces: workspaces,
    sort: sort,
    favoriteWorkspaceIds: favoriteWorkspaceIds,
    sessionCountByWorkspaceId: sessionCounts,
    displayName: displayName,
    preserveOrder: preserveOrder,
  );
  return WorkspaceDisplay(
    sortedWorkspaces: sortedWorkspaces,
    sessionCounts: sessionCounts,
  );
}
