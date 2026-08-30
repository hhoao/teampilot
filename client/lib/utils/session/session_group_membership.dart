import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../models/app_session.dart';
import '../../models/session_group.dart';
import '../../models/workspace.dart';

/// Live member session ids for one manual group in one workspace.
///
/// Ignores [AppSession.display] / working bits so agent turns do not rebuild
/// the group shell. Row text still uses [SessionRowContent] on each tile.
@immutable
class SessionGroupMembership {
  const SessionGroupMembership(this.sessionIds);

  final List<String> sessionIds;

  int get length => sessionIds.length;

  factory SessionGroupMembership.from({
    required ChatState chatState,
    required SessionGroup group,
    required Workspace workspace,
  }) {
    final inWorkspace = <String>{};
    for (final session in chatState.sessions) {
      if (session.workspaceId == workspace.workspaceId && !session.archived) {
        inWorkspace.add(session.sessionId);
      }
    }
    return SessionGroupMembership([
      for (final id in group.sessionIds)
        if (inWorkspace.contains(id)) id,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! SessionGroupMembership) return false;
    final a = sessionIds;
    final b = other.sessionIds;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final id in sessionIds) {
      hash = Object.hash(hash, id);
    }
    return hash;
  }
}

/// Group member ids resolved to live sessions of [workspace], preserving group
/// order and dropping unknown/other-workspace ids.
List<AppSession> liveGroupMembers(
  ChatState chatState,
  SessionGroup group,
  Workspace workspace,
) {
  final byId = {for (final s in chatState.sessions) s.sessionId: s};
  return [
    for (final id in group.sessionIds)
      if (byId[id] case final session?)
        if (session.workspaceId == workspace.workspaceId) session,
  ];
}
