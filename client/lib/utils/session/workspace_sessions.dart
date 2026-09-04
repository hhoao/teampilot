import '../../l10n/app_localizations.dart';
import '../../models/workspace.dart';
import '../../models/app_session.dart';
import 'session_display_title.dart';

/// Sessions for [workspace] in workspace order, then any orphans for that workspace.
List<AppSession> sessionsForWorkspace(
  Workspace workspace,
  List<AppSession> all,
) {
  final byId = {
    for (final s in all)
      if (s.workspaceId == workspace.workspaceId) s.sessionId: s,
  };
  final ordered = <AppSession>[];
  final seen = <String>{};
  for (final id in workspace.sessionIds) {
    final s = byId[id];
    if (s == null) continue;
    ordered.add(s);
    seen.add(id);
  }
  for (final s in all) {
    if (s.workspaceId != workspace.workspaceId) continue;
    if (seen.contains(s.sessionId)) continue;
    ordered.add(s);
    seen.add(s.sessionId);
  }
  return ordered;
}

/// All [sessions] grouped by [AppSession.workspaceId]. Order within each bucket
/// matches [all] iteration order.
Map<String, List<AppSession>> groupSessionsByWorkspaceId(List<AppSession> all) {
  final grouped = <String, List<AppSession>>{};
  for (final session in all) {
    final workspaceId = session.workspaceId;
    if (workspaceId.isEmpty) continue;
    grouped.putIfAbsent(workspaceId, () => []).add(session);
  }
  return grouped;
}

/// Case-insensitive filter on resolved title and session id.
List<AppSession> filterSessionsByQuery(
  List<AppSession> sessions, {
  required String query,
  required AppLocalizations l10n,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sessions;
  return [
    for (final session in sessions)
      if (_sessionMatchesQuery(session, query: q, l10n: l10n)) session,
  ];
}

bool _sessionMatchesQuery(
  AppSession session, {
  required String query,
  required AppLocalizations l10n,
}) {
  final title = sessionListDisplayTitle(session, l10n).toLowerCase();
  if (title.contains(query)) return true;
  if (session.display.toLowerCase().contains(query)) return true;
  return session.sessionId.toLowerCase().contains(query);
}
