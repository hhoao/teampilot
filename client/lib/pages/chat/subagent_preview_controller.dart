import 'package:flutter/foundation.dart';

/// Stack of subagent preview [toolCallId]s for the Chat overlay.
class SubagentPreviewController extends ChangeNotifier {
  final List<String> _stack = <String>[];

  List<String> get stack => List<String>.unmodifiable(_stack);

  void push(String toolCallId) {
    _stack.add(toolCallId);
    notifyListeners();
  }

  void pop() {
    if (_stack.isEmpty) return;
    _stack.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_stack.isEmpty) return;
    _stack.clear();
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
