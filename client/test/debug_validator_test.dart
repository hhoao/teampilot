import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_export.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import 'support/flush_terminal_engine.dart';

class _FakeTransport implements TerminalTransport {
  @override
  Stream<Uint8List> get output => const Stream.empty();

  @override
  Future<int> get done => Future.value(0);

  @override
  void close() {}

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

void main() {
  test('exact copy with FakeTransport', () async {
    var started = false;
    final session = TerminalSession(
      executable: '/tmp/teampilot-missing-flashskyai-executable',
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            started = true;
            return Future.value(_FakeTransport());
          },
    );
    addTearDown(session.dispose);

    session.connect(workingDirectory: Directory.current.path);
    session.onViewportResize(80, 24);
    await flushTerminalEngine(session.engine);

    expect(started, isFalse);
  });
}
