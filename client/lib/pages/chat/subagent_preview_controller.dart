import 'package:flutter/foundation.dart';

/// Stack of subagent preview [toolCallId]s for the Chat overlay.
class SubagentPreviewController extends ChangeNotifier {
  final List<String> _stack = <String>[];

  /// Back-to-parent stops auto-follow for the rest of this session.
  bool _followStopped = false;

  /// Last id closed by back; it never re-opens automatically.
  String? _followUntilId;

  List<String> get stack => List<String>.unmodifiable(_stack);

  /// True once the user backed out of a preview to the parent conversation.
  bool get followStopped => _followStopped;

  void push(String toolCallId) {
    _stack.add(toolCallId);
    notifyListeners();
  }

  /// Applies a [computeAutoFollow] result (deferred to post-frame by callers).
  void autoOpen(String toolCallId) {
    if (_stack.contains(toolCallId)) return;
    push(toolCallId);
  }

  /// Pure: returns the id to auto-open, or null. Safe to call during build —
  /// never notifies. [runningIds] must be newest-first; the first id that is
  /// not handled, not already open, and has an inflated attachment wins.
  String? computeAutoFollow({
    required bool prefEnabled,
    required List<String> runningIds,
    required Set<String> availableIds,
  }) {
    if (!prefEnabled || _followStopped) return null;
    for (final id in runningIds) {
      if (id == _followUntilId) continue;
      if (_stack.contains(id)) continue;
      if (!availableIds.contains(id)) continue;
      return id;
    }
    return null;
  }

  /// Back from the preview: pops one level. Returning to the parent
  /// conversation stops auto-follow for this session.
  void popAndStopFollow() {
    if (_stack.isEmpty) return;
    final popped = _stack.removeLast();
    if (_stack.isEmpty) {
      _followStopped = true;
      _followUntilId = popped;
    }
    notifyListeners();
  }

  void resetFollow() {
    _followStopped = false;
    _followUntilId = null;
  }

  void clear() {
    if (_stack.isEmpty && !_followStopped && _followUntilId == null) return;
    _stack.clear();
    resetFollow();
    notifyListeners();
  }

  /// Keep the longest valid prefix from the root. Silent — no [notifyListeners].
  void pruneToAvailable(Set<String> available) {
    var keep = 0;
    while (keep < _stack.length && available.contains(_stack[keep])) {
      keep++;
    }
    if (keep < _stack.length) {
      _stack.removeRange(keep, _stack.length);
    }
  }
}
