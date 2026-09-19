// client/lib/services/compose/compose_clip.dart
import 'package:flutter/foundation.dart';

/// Holds a paste-collapsed block of text that is kept out of the visible
/// compose field (which would otherwise lay out every line). Owned by the
/// compose parent (e.g. `SessionChatView`) and threaded down through the
/// compose card into `ComposeTriggerField`.
class ComposeClip extends ChangeNotifier {
  String _text = '';

  bool get collapsed => _text.isNotEmpty;

  /// The full block text, or null when not collapsed.
  String? get text => _text.isEmpty ? null : _text;

  /// Line count (newline count + 1) of the block, or 1 when empty.
  int get lineCount => countLines(_text);

  /// Collapse with the whole current draft (e.g. right after an oversized
  /// paste). The caller clears the visible controller afterwards.
  ///
  /// A second oversized paste into the follow-up input appends to the existing
  /// block (joined with a newline) instead of replacing it, so the block never
  /// drops earlier pasted content and a single badge keeps a running line
  /// count. When the clip is empty, the merge is the plain [fullText].
  void setPasted(String fullText) {
    final merged = _text.isEmpty ? fullText : '$_text\n$fullText';
    if (_text == merged) return;
    _text = merged;
    notifyListeners();
  }

  /// Write-back from the full-screen editor. Stays collapsed; line count may
  /// change. An empty write-back clears the clip (collapsed becomes false).
  void setExpanded(String newText) {
    if (_text == newText) return;
    _text = newText;
    notifyListeners();
  }

  /// Final message: non-empty parts joined with a blank line (block first).
  String composeMessage(String followUp) {
    final block = _text.trim();
    final tail = followUp.trim();
    if (block.isEmpty) return tail;
    if (tail.isEmpty) return block;
    return '$block\n\n$tail';
  }

  void clear() {
    if (_text.isEmpty) return;
    _text = '';
    notifyListeners();
  }

  /// Line count = `'\n'` count + 1. Deterministic and O(n) — matches the
  /// reference mockup's "152 lines" counting and never needs text layout.
  static int countLines(String text) {
    if (text.isEmpty) return 1;
    var count = 1;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) count++;
    }
    return count;
  }
}
