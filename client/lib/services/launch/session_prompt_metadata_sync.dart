import 'dart:async';

import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../repositories/session_repository.dart';
import '../../utils/session_display_title.dart';

/// Auto-rename and debounced touch hooks driven by first/every user prompt lines.
class SessionPromptMetadataSync {
  SessionPromptMetadataSync({
    required SessionLaunchHost host,
    required ChatState Function() state,
  }) : _host = host,
       _state = state;

  final SessionLaunchHost _host;
  final ChatState Function() _state;
  final _lastTouchTimes = <String, int>{};

  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    final repo = _host.sessionRepository;
    if (repo == null) return null;
    return (line) {
      unawaited(_maybeAutoRenameFromFirstPrompt(repo, sessionId, line));
    };
  }

  /// Bumps session updatedAt on every user-submitted line (debounced per
  /// session: at most once every 5 seconds).
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    final repo = _host.sessionRepository;
    if (repo == null) return null;
    return (line) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastTouchTimes[sessionId] ?? 0;
      if (now - last < 5000) return;
      _lastTouchTimes[sessionId] = now;
      unawaited(repo.touchSession(sessionId));
      if (_host.isClosed) return;
      final state = _state();
      _host.applyState(
        state.copyWith(
          sessions: state.sessions.map((s) {
            if (s.sessionId != sessionId) return s;
            return s.copyWith(updatedAt: now);
          }).toList(),
        ),
      );
    };
  }

  Future<void> _maybeAutoRenameFromFirstPrompt(
    SessionRepository repo,
    String sessionId,
    String firstPrompt,
  ) async {
    if (_host.isClosed) return;
    AppSession? session;
    for (final s in _state().sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null || session.display.trim().isNotEmpty) return;
    final title = deriveSessionTitleFromFirstPrompt(firstPrompt);
    if (title.isEmpty) return;
    await _host.renameSession(repo, sessionId, title);
  }
}
