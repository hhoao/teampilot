import 'package:flutter/foundation.dart';

/// Shared navigation state between a [DiffToolbar] and a diff body (side-by-side
/// or unified). The toolbar drives [next]/[previous]; the body listens and
/// scrolls the focused change into view, translating [current] into its own
/// layout. The body keeps [changeCount] in sync after each diff computation.
class DiffViewController extends ChangeNotifier {
  int _changeCount = 0;
  int _current = -1;

  int get changeCount => _changeCount;

  /// The focused change index, or -1 when none is focused yet.
  int get current => _current;

  set changeCount(int value) {
    final next = value < 0 ? 0 : value;
    if (next == _changeCount) return;
    _changeCount = next;
    if (_current >= next) _current = next - 1;
    notifyListeners();
  }

  void next() => _move(1);
  void previous() => _move(-1);

  void _move(int delta) {
    if (_changeCount == 0) return;
    final raw = _current < 0
        ? (delta > 0 ? 0 : _changeCount - 1)
        : (_current + delta) % _changeCount;
    _current = raw < 0 ? raw + _changeCount : raw;
    notifyListeners();
  }
}
