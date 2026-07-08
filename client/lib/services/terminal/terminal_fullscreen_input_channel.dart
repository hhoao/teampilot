import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../utils/logger.dart';

/// Serialized bracketed-paste + CR injections for full-screen TUI CLIs.
///
/// DIP: depends on a narrow write delegate, not [TerminalSession] itself.
final class TerminalFullscreenInputChannel {
  TerminalFullscreenInputChannel({required void Function(String text) writeToPty})
    : _writeToPty = writeToPty;

  final void Function(String text) _writeToPty;

  /// Settle window between bracketed-paste content and the standalone CR for
  /// full-screen TUI CLIs, matching Claude Code's own ~10ms child-PTY delay.
  static const fullScreenSubmitDelay = Duration(milliseconds: 10);

  Future<void> _ptySubmitChain = Future<void>.value();

  Future<void> pasteText(String text) {
    final next = _ptySubmitChain.then((_) async {
      _writeToPty('\x1B[200~$text\x1B[201~');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> clearInputLine() {
    final next = _ptySubmitChain.then((_) async {
      _writeToPty('\x15');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> clearStagedInput({int killLines = 3}) {
    final next = _ptySubmitChain.then((_) async {
      for (var i = 0; i < killLines; i++) {
        _writeToPty('\x15');
        if (i < killLines - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> submitFullScreenInput(
    String text, {
    Duration? pasteSettleDelay,
    required Duration defaultSettleDelay,
    required void Function() onTurnStart,
  }) {
    onTurnStart();
    final delay = pasteSettleDelay ?? defaultSettleDelay;
    appLogger.d(
      '[terminal] fullscreen-inject paste chars=${text.length} '
      'settleMs=${delay.inMilliseconds}',
    );
    final next = _ptySubmitChain.then((_) async {
      _writeToPty('\x1B[200~$text\x1B[201~');
      await Future<void>.delayed(delay);
      appLogger.d('[terminal] fullscreen-inject cr');
      _writeToPty('\r');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> submitPendingCr() {
    appLogger.d('[terminal] nudge-cr-only');
    final next = _ptySubmitChain.then((_) async {
      _writeToPty('\r');
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  void writeln(String text, {required void Function() onTurnStart}) {
    onTurnStart();
    _writeToPty('$text\r');
  }

  void writeRaw(String text) => _writeToPty(text);

  void writeBytes(Uint8List data) =>
      _writeToPty(utf8.decode(data, allowMalformed: true));
}
