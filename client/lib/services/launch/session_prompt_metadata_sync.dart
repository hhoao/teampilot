import 'dart:async';

import '../../cubits/chat/model/chat_state.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../repositories/session_repository.dart';
import '../../utils/session/session_display_title.dart';

/// Minimum gap between [touchOnUserActivity] persists for one session.
const sessionActivityTouchDebounceMs = 5000;

/// Auto-rename and debounced touch hooks driven by user activity.
class SessionPromptMetadataSync {
  SessionPromptMetadataSync({
    required SessionLaunchHost host,
    required ChatState Function() state,
    int Function()? nowMs,
  }) : _host = host,
       _state = state,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final SessionLaunchHost _host;
  final ChatState Function() _state;
  final int Function() _nowMs;
  final _lastTouchTimes = <String, int>{};

  void Function(String line)? autoRenameOnFirstPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    if (_host.sessionRepository == null) return null;
    return (line) {
      unawaited(applyFirstPromptTitle(sessionId, line));
    };
  }

  /// Renames an untitled session from the first operator prompt.
  ///
  /// Used by keyboard capture and compose-landing PTY inject (which bypasses
  /// [FirstUserLineCapture]).
  Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) async {
    if (sessionId.startsWith('local-')) return;
    final repo = _host.sessionRepository;
    if (repo == null) return;
    await _maybeAutoRenameFromFirstPrompt(repo, sessionId, firstPrompt);
  }

  /// Bumps [AppSession.updatedAt] for user activity (compose inject, mailbox,
  /// keyboard Enter). Debounced per session.
  void touchOnUserActivity(String sessionId) {
    if (sessionId.startsWith('local-')) return;
    final repo = _host.sessionRepository;
    if (repo == null) return;
    final now = _nowMs();
    final last = _lastTouchTimes[sessionId] ?? 0;
    if (now - last < sessionActivityTouchDebounceMs) return;
    _lastTouchTimes[sessionId] = now;
    unawaited(repo.touchSession(sessionId));
    if (_host.isClosed) return;
    AppSession? current;
    for (final s in _state().sessions) {
      if (s.sessionId == sessionId) {
        current = s;
        break;
      }
    }
    if (current == null) return;
    _host.replaceSessionSnapshot(current.copyWith(updatedAt: now));
  }

  /// Keyboard path: [EveryUserLineCapture] already drops blank submits.
  void Function(String line)? autoTouchOnEveryPrompt(String sessionId) {
    if (sessionId.startsWith('local-')) return null;
    if (_host.sessionRepository == null) return null;
    return (_) => touchOnUserActivity(sessionId);
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
