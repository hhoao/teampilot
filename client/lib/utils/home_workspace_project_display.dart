import '../models/app_project.dart';
import '../models/app_session.dart';
import '../pages/home_workspace/home_workspace_project_sort.dart';

class HomeWorkspaceProjectDisplay {
  const HomeWorkspaceProjectDisplay({
    required this.sortedProjects,
    required this.sessionCounts,
  });

  final List<AppProject> sortedProjects;
  final Map<String, int> sessionCounts;
}

/// Sorts [projects] and counts sessions. Returns the previous [cached] result
/// when all inputs are unchanged (reference equality on lists/maps).
HomeWorkspaceProjectDisplay computeHomeWorkspaceProjectDisplay({
  required List<AppProject> projects,
  required List<AppSession> sessions,
  required HomeWorkspaceProjectSort sort,
  required Set<String> favoriteProjectIds,
  required String Function(AppProject project) displayName,
  bool preserveOrder = false,
  HomeWorkspaceProjectDisplay? cached,
  List<AppProject>? lastProjects,
  List<AppSession>? lastSessions,
  HomeWorkspaceProjectSort? lastSort,
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
  final sortedProjects = sortHomeWorkspaceProjects(
    projects: projects,
    sort: sort,
    favoriteProjectIds: favoriteProjectIds,
    sessionCountByProjectId: sessionCounts,
    displayName: displayName,
    preserveOrder: preserveOrder,
  );
  return HomeWorkspaceProjectDisplay(
    sortedProjects: sortedProjects,
    sessionCounts: sessionCounts,
  );
}
