import 'package:path/path.dart' as p;

/// Single source of truth for the on-disk layout of one chat session.
///
/// Every artifact belonging to a session lives under one self-contained
/// directory, so creating, listing and deleting a session is a single
/// directory operation:
///
/// ```
/// {appProjectsDir}/sessions/{sessionId}/
///   session.json           # AppSession metadata
///   bus-mail/{role}.jsonl  # team message bus event logs
///   bus-tasks/tasks.jsonl  # shared task queue log
/// ```
class SessionStorageLayout {
  const SessionStorageLayout({
    required this.sessionsDir,
    required p.Context context,
  }) : _ctx = context;

  /// Builds the layout rooted at `{appProjectsDir}/sessions`.
  factory SessionStorageLayout.forProjectsDir(
    String appProjectsDir,
    p.Context context,
  ) => SessionStorageLayout(
    sessionsDir: context.join(appProjectsDir, 'sessions'),
    context: context,
  );

  /// `{appProjectsDir}/sessions` — parent of every per-session directory.
  final String sessionsDir;
  final p.Context _ctx;

  /// `{sessionsDir}/{sessionId}` — the self-contained directory for one session.
  String sessionDir(String sessionId) => _ctx.join(sessionsDir, sessionId);

  /// `{sessionDir}/session.json` — the [AppSession] metadata file.
  String sessionFile(String sessionId) =>
      _ctx.join(sessionsDir, sessionId, 'session.json');

  /// `{sessionDir}/bus-mail` — per-member message bus JSONL logs.
  String busMailDir(String sessionId) =>
      _ctx.join(sessionsDir, sessionId, 'bus-mail');

  /// `{sessionDir}/bus-tasks` — shared task queue JSONL log.
  String busTasksDir(String sessionId) =>
      _ctx.join(sessionsDir, sessionId, 'bus-tasks');
}
