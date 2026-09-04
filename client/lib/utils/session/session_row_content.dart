import 'package:flutter/foundation.dart';

import '../../cubits/chat/model/chat_state.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_session.dart';
import 'session_display_title.dart';

/// Painted sidebar / tab-chip title + relative-time inputs for one session.
@immutable
class SessionRowContent {
  const SessionRowContent({
    required this.sessionId,
    required this.display,
    required this.purpose,
    required this.updatedAt,
    required this.createdAt,
  });

  final String sessionId;
  final String display;
  final SessionPurpose purpose;
  final int updatedAt;
  final int createdAt;

  /// Locale-aware title for [Text] — never paint from a stale widget field.
  String titleForPaint(AppLocalizations l10n) => resolveSessionListTitle(
    purpose: purpose,
    display: display,
    l10n: l10n,
  );

  /// Timestamp used for relative-time labels (`updatedAt` with `createdAt` fallback).
  int get timestampMsForPaint => updatedAt != 0 ? updatedAt : createdAt;

  factory SessionRowContent.fromSession(AppSession session) {
    return SessionRowContent(
      sessionId: session.sessionId,
      display: session.display,
      purpose: session.purpose,
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
      purpose: SessionPurpose.normal,
      updatedAt: 0,
      createdAt: 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionRowContent &&
        sessionId == other.sessionId &&
        display == other.display &&
        purpose == other.purpose &&
        updatedAt == other.updatedAt &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, display, purpose, updatedAt, createdAt);
}
