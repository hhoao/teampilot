import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../models/app_session.dart';

/// Painted sidebar / tab-chip title + relative-time inputs for one session.
@immutable
class SessionRowContent {
  const SessionRowContent({
    required this.sessionId,
    required this.display,
    required this.updatedAt,
    required this.createdAt,
  });

  final String sessionId;
  final String display;
  final int updatedAt;
  final int createdAt;

  /// Title string for [Text] — never paint from a stale widget field instead.
  String get titleForPaint => display;

  /// Timestamp used for relative-time labels (`updatedAt` with `createdAt` fallback).
  int get timestampMsForPaint => updatedAt != 0 ? updatedAt : createdAt;

  factory SessionRowContent.fromSession(AppSession session) {
    return SessionRowContent(
      sessionId: session.sessionId,
      display: session.display,
      updatedAt: session.updatedAt,
      createdAt: session.createdAt,
    );
  }

  factory SessionRowContent.fromChatState(ChatState state, String sessionId) {
    for (final s in state.sessions) {
      if (s.sessionId == sessionId) return SessionRowContent.fromSession(s);
    }
    return SessionRowContent(
      sessionId: sessionId,
      display: '',
      updatedAt: 0,
      createdAt: 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionRowContent &&
        sessionId == other.sessionId &&
        display == other.display &&
        updatedAt == other.updatedAt &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode => Object.hash(sessionId, display, updatedAt, createdAt);
}
