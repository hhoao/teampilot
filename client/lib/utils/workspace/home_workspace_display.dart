import '../../models/workspace.dart';
import '../../models/app_session.dart';
import '../../pages/home_workspace/workspace_sort.dart';

/// Case-insensitive substring match on display name, id, and folder paths.
List<Workspace> filterWorkspacesByQuery({
  required List<Workspace> workspaces,
  required String query,
  required String Function(Workspace workspace) displayName,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return workspaces;
  }
  return [
    for (final workspace in workspaces)
      if (_workspaceMatchesFilter(
        workspace,
        needle: needle,
        displayName: displayName(workspace),
      ))
        workspace,
  ];
}

bool _workspaceMatchesFilter(
  Workspace workspace, {
  required String needle,
  required String displayName,
}) {
  if (displayName.toLowerCase().contains(needle)) {
    return true;
  }
  if (workspace.display.toLowerCase().contains(needle)) {
    return true;
  }
  if (workspace.workspaceId.toLowerCase().contains(needle)) {
    return true;
  }
  for (final folder in workspace.folders) {
    if (folder.path.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

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

  final sessionCounts = homeWorkspaceSessionCountByWorkspaceId(
    sessions,
    workspaces: workspaces,
  );
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
