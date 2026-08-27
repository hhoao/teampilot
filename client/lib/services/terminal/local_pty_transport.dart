import 'dart:typed_data';
import 'package:flutter_pty_new/flutter_pty_new.dart';
import 'terminal_transport.dart';

class LocalPtyTransport implements TerminalTransport {
  LocalPtyTransport(this._pty);

  final Pty _pty;
  bool _closed = false;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  Future<int> get done => _pty.exitCode;

  @override
  int? get pid {
    final p = _pty.pid;
    return p > 0 ? p : null;
  }

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
    if (_closed) return;
    _closed = true;
    try {
      _pty.kill();
    } finally {
      _pty.dispose();
    }
  }
}
