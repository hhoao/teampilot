import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../models/app_session.dart';

/// Library-visible session bits. Title capture / CLI identity changes that
/// do not affect these fields must not rebuild the home workspace grid.
@immutable
class HomeSessionsPaintView {
  const HomeSessionsPaintView(this.sessions);

  final List<AppSession> sessions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HomeSessionsPaintView) return false;
    if (other.sessions.length != sessions.length) return false;
    for (var i = 0; i < sessions.length; i++) {
      final a = sessions[i];
      final b = other.sessions[i];
      if (a.sessionId != b.sessionId ||
          a.workspaceId != b.workspaceId ||
          a.display != b.display ||
          a.createdAt != b.createdAt ||
          a.updatedAt != b.updatedAt) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    for (final s in sessions)
      Object.hash(
        s.sessionId,
        s.workspaceId,
        s.display,
        s.createdAt,
        s.updatedAt,
      ),
  ]);
}

/// [context.select] that ignores session fields the library cards do not paint.
List<AppSession> watchHomeLibrarySessions(BuildContext context) {
  return context
      .select<ChatCubit, HomeSessionsPaintView>(
        (c) => HomeSessionsPaintView(c.state.sessions),
      )
      .sessions;
}
