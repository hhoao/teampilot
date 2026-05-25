import 'dart:typed_data';
import 'package:flutter_pty/flutter_pty.dart';
import 'terminal_transport.dart';

class LocalPtyTransport implements TerminalTransport {
  LocalPtyTransport(this._pty);

  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  Future<int> get done => _pty.exitCode;

  @override
  void write(Uint8List data) {
    _pty.write(data);
  }

  @override
  void resize(int rows, int columns) {
    _pty.resize(rows, columns);
  }

  @override
  void close() {
    _pty.kill();
  }
}
