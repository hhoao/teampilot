import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../utils/logging/logger.dart';
import 'terminal_input_command_queue.dart';

/// Serialized bracketed-paste + CR injections for full-screen TUI CLIs.
///
/// DIP: depends on a narrow write delegate, not [TerminalSession] itself.
final class TerminalFullscreenInputChannel {
  TerminalFullscreenInputChannel({
    void Function(String text)? writeToPty,
    TerminalInputCommandQueue? commands,
  }) : assert(writeToPty != null || commands != null),
       _commands =
           commands ?? TerminalInputCommandQueue(write: writeToPty!);

  final TerminalInputCommandQueue _commands;

  /// Settle window between bracketed-paste content and the standalone CR for
  /// full-screen TUI CLIs, matching Claude Code's own ~10ms child-PTY delay.
  static const fullScreenSubmitDelay = Duration(milliseconds: 10);

  /// Keep each PTY write under typical pipe atomicity so a single short write
  /// cannot truncate the bracketed-paste terminator on large payloads.
  static const ptyWriteChunkChars = 1024;

  Future<void> _ptySubmitChain = Future<void>.value();

  Future<void> _writeChunked(String text, {bool Function()? canExecute}) async {
    final fence = canExecute ?? _always;
    if (text.length <= ptyWriteChunkChars) {
      await _commands.enqueue(
        TerminalInputCommand.bytes(text, canExecute: fence),
      );
      return;
    }
    for (var i = 0; i < text.length; i += ptyWriteChunkChars) {
      final end = math.min(i + ptyWriteChunkChars, text.length);
      final result = await _commands.enqueue(
        TerminalInputCommand.bytes(text.substring(i, end), canExecute: fence),
      );
      if (result == TerminalInputCommandResult.dropped) return;
    }
  }

  Future<void> pasteText(String text, {bool Function()? canExecute}) {
    final next = _ptySubmitChain.then((_) async {
      await _writeChunked('\x1B[200~$text\x1B[201~', canExecute: canExecute);
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> clearInputLine() {
    final next = _ptySubmitChain.then((_) async {
      await _commands.enqueue(
        TerminalInputCommand.bytes('\x15', canExecute: _always),
      );
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> clearStagedInput({int killLines = 3}) {
    final next = _ptySubmitChain.then((_) async {
      for (var i = 0; i < killLines; i++) {
        await _commands.enqueue(
          TerminalInputCommand.bytes('\x15', canExecute: _always),
        );
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
    bool Function()? canExecute,
  }) {
    onTurnStart();
    final delay = pasteSettleDelay ?? defaultSettleDelay;
    appLogger.d(
      '[terminal] fullscreen-inject paste chars=${text.length} '
      'settleMs=${delay.inMilliseconds}',
    );
    final next = _ptySubmitChain.then((_) async {
      await _writeChunked('\x1B[200~$text\x1B[201~', canExecute: canExecute);
      await Future<void>.delayed(delay);
      appLogger.d('[terminal] fullscreen-inject cr');
      await _commands.enqueue(
        TerminalInputCommand.bytes('\r', canExecute: canExecute ?? _always),
      );
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  Future<void> submitPendingCr({bool Function()? canExecute}) {
    appLogger.d('[terminal] nudge-cr-only');
    final next = _ptySubmitChain.then((_) async {
      await _commands.enqueue(
        TerminalInputCommand.bytes('\r', canExecute: canExecute ?? _always),
      );
    });
    _ptySubmitChain = next.catchError((_) {});
    return next;
  }

  void writeln(String text, {required void Function() onTurnStart}) {
    onTurnStart();
    unawaited(
      _commands.enqueue(
        TerminalInputCommand.bytes('$text\r', canExecute: _always),
      ),
    );
  }

  void writeRaw(String text) => unawaited(
    _commands.enqueue(TerminalInputCommand.bytes(text, canExecute: _always)),
  );

  void writeBytes(Uint8List data) =>
      writeRaw(utf8.decode(data, allowMalformed: true));
}

bool _always() => true;
