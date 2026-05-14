import 'dart:async';
import 'dart:typed_data';

import 'package:teampilot/services/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePtyHandle implements TerminalPtyHandle {
  final outputController = StreamController<Uint8List>();
  final exitCompleter = Completer<int>();
  var killed = false;
  final resizeCalls = <(int, int)>[];
  final writes = <Uint8List>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void kill() {
    killed = true;
    if (!exitCompleter.isCompleted) {
      exitCompleter.complete(0);
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
}

void main() {
  test('connect starts pty immediately before terminal resize', () async {
    final starts = <({int columns, int rows})>[];
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: 'flashskyai',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            starts.add((columns: columns, rows: rows));
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: '/tmp');

    expect(starts, [(columns: 80, rows: 24)]);
    expect(session.isRunning, isTrue);
  });

  test('terminal resize resizes an already-started pty', () async {
    final handle = _FakePtyHandle();
    final session = TerminalSession(
      executable: 'flashskyai',
      ptyStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return handle;
          },
    );
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: '/tmp');
    session.terminal.onResize?.call(120, 32, 0, 0);

    expect(handle.resizeCalls, [(32, 120)]);
  });
}
