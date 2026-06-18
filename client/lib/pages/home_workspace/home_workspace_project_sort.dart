import '../../l10n/app_localizations.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';

enum WorkspaceSort {
  recentlyUpdated,
  nameAsc,
  nameDesc,
  createdDesc,
  sessionCountDesc,
}

extension WorkspaceSortLabels on WorkspaceSort {
  String label(AppLocalizations l10n) => switch (this) {
    WorkspaceSort.recentlyUpdated =>
      l10n.homeWorkspaceProjectSortRecentlyUpdated,
    WorkspaceSort.nameAsc => l10n.homeWorkspaceProjectSortNameAsc,
    WorkspaceSort.nameDesc => l10n.homeWorkspaceProjectSortNameDesc,
    WorkspaceSort.createdDesc =>
      l10n.homeWorkspaceProjectSortCreatedDesc,
    WorkspaceSort.sessionCountDesc =>
      l10n.homeWorkspaceProjectSortSessionCountDesc,
  };

  static WorkspaceSort parse(String? raw) {
    for (final value in WorkspaceSort.values) {
      if (value.name == raw) return value;
    }
    return WorkspaceSort.recentlyUpdated;
  }
}

Map<String, int> homeWorkspaceSessionCountByProjectId(
  List<AppSession> sessions,
) {
  final counts = <String, int>{};
  for (final session in sessions) {
    final id = session.projectId;
    if (id.isEmpty) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}

List<Workspace> sortWorkspaces({
  required List<Workspace> projects,
  required WorkspaceSort sort,
  required Set<String> favoriteProjectIds,
  required Map<String, int> sessionCountByProjectId,
  required String Function(Workspace project) displayName,
  bool pinFavorites = true,
  bool preserveOrder = false,
}) {
  if (preserveOrder) return List<Workspace>.from(projects);

  final sorted = List<Workspace>.from(projects);
  sorted.sort((a, b) {
    if (pinFavorites) {
      final af = favoriteProjectIds.contains(a.projectId);
      final bf = favoriteProjectIds.contains(b.projectId);
      if (af != bf) return af ? -1 : 1;
    }

    final primary = switch (sort) {
      WorkspaceSort.recentlyUpdated =>
        b.updatedAt.compareTo(a.updatedAt),
      WorkspaceSort.nameAsc => _compareIgnoreCase(
        displayName(a),
        displayName(b),
      ),
      WorkspaceSort.nameDesc => _compareIgnoreCase(
        displayName(b),
        displayName(a),
      ),
      WorkspaceSort.createdDesc =>
        b.createdAt.compareTo(a.createdAt),
      WorkspaceSort.sessionCountDesc => () {
        final ac = sessionCountByProjectId[a.projectId] ?? 0;
        final bc = sessionCountByProjectId[b.projectId] ?? 0;
        final bySessions = bc.compareTo(ac);
        if (bySessions != 0) return bySessions;
        return b.updatedAt.compareTo(a.updatedAt);
      }(),
    };
    return primary;
  });
  return sorted;
}

int _compareIgnoreCase(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());
