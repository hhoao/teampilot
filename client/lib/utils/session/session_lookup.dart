import '../../models/app_session.dart';

/// Single-entry session index over `ChatState.sessions` for UI-isolate reads.
///
/// `context.select` runs its selector on every ChatCubit emit — including the
/// per-chunk activity emits of running terminals — for every mounted sidebar
/// row, tab chip, and header. In large workspaces (1500+ sessions) a linear
/// scan per read turns those emits into milliseconds of repeated work.
///
/// `ChatState` replaces the sessions list wholesale on content changes, so the
/// index built for the previous identity stays valid while the identity holds.
/// A single-entry cache is enough: readers of one state all share one list.
abstract final class SessionLookup {
  static List<AppSession>? _source;
  static Map<String, AppSession> _index = const {};

  static Map<String, AppSession> indexOf(List<AppSession> sessions) {
    if (identical(sessions, _source)) return _index;
    _source = sessions;
    _index = {for (final session in sessions) session.sessionId: session};
    return _index;
  }

  static AppSession? byId(List<AppSession> sessions, String sessionId) =>
      indexOf(sessions)[sessionId];
}
