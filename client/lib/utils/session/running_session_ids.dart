import 'package:flutter/foundation.dart';

import '../../models/app_session.dart';
import 'workspace_running_sessions.dart';

/// Order-sensitive Running-strip membership for [context.select].
@immutable
class RunningSessionIds {
  const RunningSessionIds(this.ids);

  final List<String> ids;

  bool get isEmpty => ids.isEmpty;

  factory RunningSessionIds.fromWorkspace({
    required List<AppSession> sessions,
    required Set<String> busySessionIds,
    required Set<String> openTabSessionIds,
  }) {
    final running = workspaceRunningSessions(
      sessions: sessions,
      busySessionIds: busySessionIds,
      openTabSessionIds: openTabSessionIds,
    );
    return RunningSessionIds([for (final s in running) s.sessionId]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! RunningSessionIds) return false;
    final a = ids;
    final b = other.ids;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final id in ids) {
      hash = Object.hash(hash, id);
    }
    return hash;
  }
}
