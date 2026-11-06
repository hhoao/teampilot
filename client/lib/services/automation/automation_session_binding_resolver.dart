import '../../models/app_session.dart';
import '../../models/automation.dart';
import '../../models/team_config.dart';
import '../../utils/session/app_session_sort.dart';
import '../../utils/session/session_archive_filter.dart';

/// Resolves the current binding target. [sessions] is already scoped to the
/// automation's workspace by the caller.
AppSession? findBoundSession(String? sessionId, List<AppSession> sessions) {
  final trimmed = sessionId?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  for (final session in sessions) {
    if (session.sessionId == trimmed) return session;
  }
  return null;
}

/// CLI to scope the preset picker to when a session is bound.
///
/// Team launch prompts have no preset picker, and an unavailable bound session
/// cannot supply a CLI — both return null (no filtering).
CliTool? bindingCliFilter(AppSession? boundSession) {
  if (boundSession == null || !boundSession.isSimple) return null;
  return boundSession.cli ?? CliTool.claude;
}

/// Sessions the automation can be rebound to, in sidebar order.
List<AppSession> bindableSessionsFor({
  required Automation automation,
  required List<AppSession> sessions,
}) {
  final filtered = activeSessions(sessions)
      .where(
        (s) =>
            s.purpose == SessionPurpose.normal && automation.matchesSession(s),
      )
      .toList(growable: false);
  return sortAppSessions(filtered, sort: AppSessionSort.recentlyUpdated);
}
