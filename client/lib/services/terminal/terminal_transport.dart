import 'dart:async';
import 'dart:typed_data';

abstract class TerminalTransport {
  Stream<Uint8List> get output;
  Future<int> get done;

  void write(Uint8List data);
  void resize(int rows, int columns);
  void close();
}
