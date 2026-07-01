import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:teampilot/services/terminal/terminal_transport.dart';

/// In-memory [TerminalTransport] that records stdin ([write]) and can push
/// synthetic PTY output into [TerminalSession]'s output stream — the same seam
/// used by [terminal_session_test.dart].
class RecordingPtyTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  Completer<int> doneCompleter = Completer<int>();
  var closed = false;
  final resizeCalls = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  void close() {
    closed = true;
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {
    resizeCalls.add((rows, columns));
  }

  @override
  void write(Uint8List data) {
    writes.add(data);
  }

  /// Push bytes into the session's PTY output path ([TerminalSession._feedPtyBytes]).
  void emitBytes(Uint8List data) {
    if (!outputController.isClosed) {
      outputController.add(data);
    }
  }

  void emitUtf8(String text) => emitBytes(Uint8List.fromList(utf8.encode(text)));

  List<String> get decodedWrites => writes.map(utf8.decode).toList();

  Future<void> dispose() async {
    close();
    await outputController.close();
  }
}
