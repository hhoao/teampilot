import '../../models/app_session.dart';

/// Sessions with an agent currently in a turn and/or a live PTY tab.
///
/// [openTabSessionIds] should be session ids that are actually running (or
/// otherwise belong in the sidebar “running” list) — not every open history
/// preview tab.
List<AppSession> workspaceRunningSessions({
  required List<AppSession> sessions,
  required Set<String> busySessionIds,
  required Set<String> openTabSessionIds,
}) {
  if (busySessionIds.isEmpty && openTabSessionIds.isEmpty) {
    return const [];
  }
  final byId = {for (final s in sessions) s.sessionId: s};
  final ordered = <AppSession>[];
  final seen = <String>{};

  void addIds(Iterable<String> ids) {
    for (final id in ids) {
      if (!seen.add(id)) continue;
      final session = byId[id];
      if (session != null) ordered.add(session);
    }
  }

  addIds(busySessionIds);
  addIds(openTabSessionIds);
  return ordered;
}

/// Open session-backed tab ids for a workspace bucket.
Set<String> openTabSessionIdsForWorkspace(Iterable<String> tabSessionIds) {
  return tabSessionIds
      .where((id) => id.isNotEmpty && !id.startsWith('local-'))
      .toSet();
}
