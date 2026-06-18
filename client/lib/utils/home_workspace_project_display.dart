import '../models/app_project.dart';
import '../models/app_session.dart';
import '../pages/home_workspace/home_workspace_project_sort.dart';

class WorkspaceDisplay {
  const WorkspaceDisplay({
    required this.sortedProjects,
    required this.sessionCounts,
  });

  final List<Workspace> sortedProjects;
  final Map<String, int> sessionCounts;
}

/// Sorts [projects] and counts sessions. Returns the previous [cached] result
/// when all inputs are unchanged (reference equality on lists/maps).
WorkspaceDisplay computeWorkspaceDisplay({
  required List<Workspace> projects,
  required List<AppSession> sessions,
  required WorkspaceSort sort,
  required Set<String> favoriteProjectIds,
  required String Function(Workspace project) displayName,
  bool preserveOrder = false,
  WorkspaceDisplay? cached,
  List<Workspace>? lastProjects,
  List<AppSession>? lastSessions,
  WorkspaceSort? lastSort,
  Set<String>? lastFavorites,
  bool? lastPreserveOrder,
}) {
  if (cached != null &&
      identical(projects, lastProjects) &&
      identical(sessions, lastSessions) &&
      sort == lastSort &&
      identical(favoriteProjectIds, lastFavorites) &&
      preserveOrder == lastPreserveOrder) {
    return cached;
  }

  final sessionCounts = homeWorkspaceSessionCountByProjectId(sessions);
  final sortedProjects = sortWorkspaces(
    projects: projects,
    sort: sort,
    favoriteProjectIds: favoriteProjectIds,
    sessionCountByProjectId: sessionCounts,
    displayName: displayName,
    preserveOrder: preserveOrder,
  );
  return WorkspaceDisplay(
    sortedProjects: sortedProjects,
    sessionCounts: sessionCounts,
  );
}
