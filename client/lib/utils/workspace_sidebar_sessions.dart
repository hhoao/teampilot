import 'package:flutter/foundation.dart';

import '../models/app_session.dart';
import '../models/workspace.dart';
import '../utils/workspace_sessions.dart';

/// Value-type snapshot for [BlocSelector] — rebuilds only when session rows
/// visible in the workspace sidebar actually change.
@immutable
class WorkspaceSidebarSessions {
  const WorkspaceSidebarSessions(this.sessions);

  final List<AppSession> sessions;

  static WorkspaceSidebarSessions forWorkspace({
    required List<AppSession> allSessions,
    required Workspace workspace,
    required String sessionTeamFilter,
  }) {
    final grouped = groupSessionsByWorkspaceId(allSessions);
    final bucket = grouped[workspace.workspaceId];
    final filtered = bucket == null || bucket.isEmpty
        ? sessionsForWorkspace(workspace, const <AppSession>[])
            .where((s) => s.sessionTeam.trim() == sessionTeamFilter)
            .toList()
        : sessionsForWorkspace(workspace, bucket)
            .where((s) => s.sessionTeam.trim() == sessionTeamFilter)
            .toList();
    return WorkspaceSidebarSessions(filtered);
  }

  @override
  bool operator ==(Object other) {
    if (other is! WorkspaceSidebarSessions) return false;
    final a = sessions;
    final b = other.sessions;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.sessionId != right.sessionId) return false;
      if (left.updatedAt != right.updatedAt) return false;
      if (left.display != right.display) return false;
      if (left.pinned != right.pinned) return false;
      if (left.sortOrder != right.sortOrder) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final s in sessions) {
      hash = Object.hash(
        hash,
        s.sessionId,
        s.updatedAt,
        s.display,
        s.pinned,
        s.sortOrder,
      );
    }
    return hash;
  }
}
