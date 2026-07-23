import 'package:flutter/foundation.dart';

import '../../models/app_session.dart';
import 'app_session_sort.dart';

/// Ordered sidebar list skeleton — ids / pin / sortOrder only (post-sort).
///
/// Ignores [AppSession.display] / [AppSession.updatedAt] so rename and
/// `touchSession` do not rebuild conversation list shells under sorts that
/// keep the same id order (e.g. [AppSessionSort.createdDesc]).
@immutable
class SessionListStructure {
  const SessionListStructure(this.rows);

  final List<SessionListStructureRow> rows;

  List<String> get sessionIds => [for (final r in rows) r.sessionId];

  factory SessionListStructure.fromSessions(
    List<AppSession> sessions, {
    required AppSessionSort sort,
  }) {
    final sorted = sortAppSessions(sessions, sort: sort);
    return SessionListStructure([
      for (final s in sorted)
        SessionListStructureRow(
          sessionId: s.sessionId,
          pinned: s.pinned,
          sortOrder: s.sortOrder,
        ),
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! SessionListStructure) return false;
    final a = rows;
    final b = other.rows;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var hash = 0;
    for (final r in rows) {
      hash = Object.hash(hash, r);
    }
    return hash;
  }
}

@immutable
class SessionListStructureRow {
  const SessionListStructureRow({
    required this.sessionId,
    required this.pinned,
    required this.sortOrder,
  });

  final String sessionId;
  final bool pinned;
  final int sortOrder;

  @override
  bool operator ==(Object other) {
    return other is SessionListStructureRow &&
        sessionId == other.sessionId &&
        pinned == other.pinned &&
        sortOrder == other.sortOrder;
  }

  @override
  int get hashCode => Object.hash(sessionId, pinned, sortOrder);
}
