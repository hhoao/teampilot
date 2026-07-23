import 'dart:async';
import 'dart:typed_data';

abstract class TerminalTransport {
  Stream<Uint8List> get output;
  Future<int> get done;

  /// Local PTY process id when available; SSH / remote transports return null.
  int? get pid;

  void write(Uint8List data);
  void resize(int rows, int columns);
  void close();
}
