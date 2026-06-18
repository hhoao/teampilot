import '../../l10n/app_localizations.dart';
import '../../models/app_workspace.dart';
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
      l10n.homeWorkspaceWorkspaceSortRecentlyUpdated,
    WorkspaceSort.nameAsc => l10n.homeWorkspaceWorkspaceSortNameAsc,
    WorkspaceSort.nameDesc => l10n.homeWorkspaceWorkspaceSortNameDesc,
    WorkspaceSort.createdDesc =>
      l10n.homeWorkspaceWorkspaceSortCreatedDesc,
    WorkspaceSort.sessionCountDesc =>
      l10n.homeWorkspaceWorkspaceSortSessionCountDesc,
  };

  static WorkspaceSort parse(String? raw) {
    for (final value in WorkspaceSort.values) {
      if (value.name == raw) return value;
    }
    return WorkspaceSort.recentlyUpdated;
  }
}

Map<String, int> homeWorkspaceSessionCountByWorkspaceId(
  List<AppSession> sessions,
) {
  final counts = <String, int>{};
  for (final session in sessions) {
    final id = session.workspaceId;
    if (id.isEmpty) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}

List<Workspace> sortWorkspaces({
  required List<Workspace> workspaces,
  required WorkspaceSort sort,
  required Set<String> favoriteWorkspaceIds,
  required Map<String, int> sessionCountByWorkspaceId,
  required String Function(Workspace workspace) displayName,
  bool pinFavorites = true,
  bool preserveOrder = false,
}) {
  if (preserveOrder) return List<Workspace>.from(workspaces);

  final sorted = List<Workspace>.from(workspaces);
  sorted.sort((a, b) {
    if (pinFavorites) {
      final af = favoriteWorkspaceIds.contains(a.workspaceId);
      final bf = favoriteWorkspaceIds.contains(b.workspaceId);
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
        final ac = sessionCountByWorkspaceId[a.workspaceId] ?? 0;
        final bc = sessionCountByWorkspaceId[b.workspaceId] ?? 0;
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
