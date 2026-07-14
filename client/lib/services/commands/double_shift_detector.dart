import 'package:flutter/services.dart';

/// Detects a JetBrains-style double Shift (two Shift key-downs within [window]
/// with no other keys in between).
class DoubleShiftDetector {
  DoubleShiftDetector({
    this.window = const Duration(milliseconds: 400),
  });

  final Duration window;

  Duration? _firstShiftDownAt;

  /// Returns `true` when [event] completes a double-Shift gesture.
  bool feed(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (_isShift(event.logicalKey)) {
      final at = event.timeStamp;
      final previous = _firstShiftDownAt;
      if (previous != null && at - previous <= window) {
        _firstShiftDownAt = null;
        return true;
      }
      _firstShiftDownAt = at;
      return false;
    }

    _firstShiftDownAt = null;
    return false;
  }

  static bool _isShift(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight;
}
