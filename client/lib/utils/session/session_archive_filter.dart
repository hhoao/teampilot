import '../../models/app_session.dart';

List<AppSession> activeSessions(List<AppSession> sessions) => [
      for (final s in sessions)
        if (!s.archived) s,
    ];

List<AppSession> archivedSessions(List<AppSession> sessions) => [
      for (final s in sessions)
        if (s.archived) s,
    ];
