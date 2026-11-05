import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/pending_branch_edit.dart';

/// One seat's optimistic user-message edit.
///
/// Owned by [ChatCubit] so a chat-area rebuild or runtime swap cannot drop the
/// optimistic bubble. The host/thread listen to this controller instead of
/// keeping their own copies of pending/draft/baseline state.
final class BranchEditController extends ChangeNotifier {
  BranchEditController({this.watchdog = const Duration(seconds: 30)});

  /// Clears an optimistic edit that never lands (e.g. a silent send failure).
  final Duration watchdog;

  PendingBranchEdit? _pending;
  String? _draft;
  String? _editingMessageId;
  Set<String> _baselineIds = const {};
  bool _hold = false;
  Timer? _timer;

  PendingBranchEdit? get pending => _pending;
  String? get draft => _draft;
  String? get editingMessageId => _editingMessageId;
  Set<String> get baselineIds => _baselineIds;

  /// Whether the old transcript must stay on screen while the edit restores
  /// and resends. A pending overlay alone is handled by the thread's
  /// pending-branch check, so it must not keep this hold latched.
  bool get holdsTranscript => _hold;

  /// Starts an edit synchronously, before the async restore path begins.
  void begin({
    required String messageId,
    required String text,
    required Iterable<String> visibleMessageIds,
  }) {
    _timer?.cancel();
    _pending = PendingBranchEdit(messageId: messageId, text: text);
    _draft = text;
    _editingMessageId = null;
    _baselineIds = visibleMessageIds.toSet();
    _hold = true;
    notifyListeners();
    _scheduleWatchdog();
  }

  void _scheduleWatchdog() {
    if (watchdog <= Duration.zero) return;
    _timer = Timer(watchdog, clearPending);
  }

  /// Used by direct API callers that do not have a visible-message list.
  void ensurePending(String messageId, String text) {
    if (_pending != null) return;
    _timer?.cancel();
    _pending = PendingBranchEdit(messageId: messageId, text: text);
    _draft ??= text;
    _baselineIds = const {};
    _hold = true;
    notifyListeners();
    _scheduleWatchdog();
  }

  /// The submit future resolved. A failed edit reopens the editor with [draft].
  void finish({required bool accepted, required String messageId}) {
    _hold = false;
    if (accepted) {
      _draft = null;
    } else {
      _editingMessageId = messageId;
    }
    notifyListeners();
  }

  void openEditor(String messageId) {
    _editingMessageId = messageId;
    notifyListeners();
  }

  void cancelEdit() {
    _editingMessageId = null;
    _draft = null;
    _baselineIds = const {};
    notifyListeners();
  }

  /// The new prompt landed; the optimistic overlay is no longer needed.
  void markLanded() => clearPending();

  void clearPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _hold = false;
    _baselineIds = const {};
    notifyListeners();
  }

  /// A runtime swap closes the inline editor but keeps the draft for a failure.
  void runtimeSwapped() {
    if (_editingMessageId == null) return;
    _editingMessageId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
