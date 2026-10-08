import 'dart:async';

/// One terminal input write guarded by the delivery state that authorized it.
final class TerminalInputCommand {
  const TerminalInputCommand.bytes(this.bytes, {required this.canExecute});

  final String bytes;
  final bool Function() canExecute;
}

/// Result of trying to perform a queued terminal input command.
enum TerminalInputCommandResult { written, dropped }

/// Serializes terminal input and evaluates each command's fence at write time.
///
/// A delivery confirmation can arrive after a command is enqueued but before
/// the PTY is available to consume it. Checking [TerminalInputCommand.canExecute]
/// here, immediately before [write], is the final fence that prevents an
/// obsolete automated paste or CR from reaching the process.
final class TerminalInputCommandQueue {
  TerminalInputCommandQueue({required void Function(String bytes) write})
    : _write = write;

  final void Function(String bytes) _write;
  Future<void> _tail = Future<void>.value();

  Future<TerminalInputCommandResult> enqueue(TerminalInputCommand command) {
    final next = _tail.then((_) {
      if (!command.canExecute()) return TerminalInputCommandResult.dropped;
      _write(command.bytes);
      return TerminalInputCommandResult.written;
    });
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
