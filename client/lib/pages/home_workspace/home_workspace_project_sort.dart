import '../../l10n/app_localizations.dart';
import '../../models/app_project.dart';
import '../../models/app_session.dart';

enum HomeWorkspaceProjectSort {
  recentlyUpdated,
  nameAsc,
  nameDesc,
  createdDesc,
  sessionCountDesc,
}

extension HomeWorkspaceProjectSortLabels on HomeWorkspaceProjectSort {
  String label(AppLocalizations l10n) => switch (this) {
    HomeWorkspaceProjectSort.recentlyUpdated =>
      l10n.homeWorkspaceProjectSortRecentlyUpdated,
    HomeWorkspaceProjectSort.nameAsc => l10n.homeWorkspaceProjectSortNameAsc,
    HomeWorkspaceProjectSort.nameDesc => l10n.homeWorkspaceProjectSortNameDesc,
    HomeWorkspaceProjectSort.createdDesc =>
      l10n.homeWorkspaceProjectSortCreatedDesc,
    HomeWorkspaceProjectSort.sessionCountDesc =>
      l10n.homeWorkspaceProjectSortSessionCountDesc,
  };

  static HomeWorkspaceProjectSort parse(String? raw) {
    for (final value in HomeWorkspaceProjectSort.values) {
      if (value.name == raw) return value;
    }
    return HomeWorkspaceProjectSort.recentlyUpdated;
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

List<AppProject> sortHomeWorkspaceProjects({
  required List<AppProject> projects,
  required HomeWorkspaceProjectSort sort,
  required Set<String> favoriteProjectIds,
  required Map<String, int> sessionCountByProjectId,
  required String Function(AppProject project) displayName,
  bool pinFavorites = true,
  bool preserveOrder = false,
}) {
  if (preserveOrder) return List<AppProject>.from(projects);

  final sorted = List<AppProject>.from(projects);
  sorted.sort((a, b) {
    if (pinFavorites) {
      final af = favoriteProjectIds.contains(a.projectId);
      final bf = favoriteProjectIds.contains(b.projectId);
      if (af != bf) return af ? -1 : 1;
    }

    final primary = switch (sort) {
      HomeWorkspaceProjectSort.recentlyUpdated =>
        b.updatedAt.compareTo(a.updatedAt),
      HomeWorkspaceProjectSort.nameAsc => _compareIgnoreCase(
        displayName(a),
        displayName(b),
      ),
      HomeWorkspaceProjectSort.nameDesc => _compareIgnoreCase(
        displayName(b),
        displayName(a),
      ),
      HomeWorkspaceProjectSort.createdDesc =>
        b.createdAt.compareTo(a.createdAt),
      HomeWorkspaceProjectSort.sessionCountDesc => () {
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
