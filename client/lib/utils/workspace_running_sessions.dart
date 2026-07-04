import '../../models/app_session.dart';

/// Sessions with an open terminal tab and/or an agent currently in a turn.
List<AppSession> workspaceRunningSessions({
  required List<AppSession> sessions,
  required Set<String> workingSessionIds,
  required Set<String> openTabSessionIds,
}) {
  if (workingSessionIds.isEmpty && openTabSessionIds.isEmpty) {
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

  addIds(workingSessionIds);
  addIds(openTabSessionIds);
  return ordered;
}

/// Open session-backed tab ids for a workspace bucket.
Set<String> openTabSessionIdsForWorkspace(Iterable<String> tabSessionIds) {
  return tabSessionIds
      .where((id) => id.isNotEmpty && !id.startsWith('local-'))
      .toSet();
}
