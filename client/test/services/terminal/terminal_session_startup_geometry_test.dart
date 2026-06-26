import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import '../../support/flush_terminal_engine.dart';

/// Passes [CliExecutableValidator] on the current platform (a real, launchable
/// path) — [connect] runs pre-flight validation before the fake transport.
String get _ptyTestExecutable {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\cmd.exe';
  }
  for (final candidate in ['/usr/bin/true', '/bin/true', '/bin/sh']) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.resolvedExecutable;
}

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  final doneCompleter = Completer<int>();
  var closed = false;
  final resizeCalls = <(int rows, int cols)>[];

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  void resize(int rows, int columns) => resizeCalls.add((rows, columns));

  @override
  void write(Uint8List data) {}

  @override
  void close() {
    closed = true;
    if (!doneCompleter.isCompleted) doneCompleter.complete(0);
  }
}

TerminalSession _sessionWithFakeTransport(_FakeTransport handle) {
  return TerminalSession(
    executable: _ptyTestExecutable,
    transportStarter:
        (
          executable, {
          required arguments,
          required workingDirectory,
          required columns,
          required rows,
          environment,
        }) {
          return Future.value(handle);
        },
  );
}

void main() {
  // Regression: [TerminalView.onPtyResize] → [onTerminalPtyResize] reports the
  // real cell grid before the deferred (Timer(0)) body of `_startTransport`. The
  // bug: that body called `engine.initializeEmpty(24, 80)`, clobbering the grid
  // the view had just sized. The mirror grid was then stuck at 24 rows inside a
  // taller viewport until a window resize re-fired resize.
  test('engine grid adopts geometry from onTerminalPtyResize before spawn',
      () async {
    final handle = _FakeTransport();
    final session = _sessionWithFakeTransport(handle);
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    // Production path: view owns engine.resize; session only records geometry
    // and SIGWINCHs the PTY once transport is ready.
    session.onTerminalPtyResize(120, 40);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await flushTerminalEngine(session.engine);

    expect(session.engine.grid.rows, 40);
    expect(session.engine.grid.columns, 120);
    expect(handle.resizeCalls, contains((40, 120)));
  });

  test('onTerminalPtyResize queues PTY SIGWINCH until transport is ready',
      () async {
    final handle = _FakeTransport();
    final session = _sessionWithFakeTransport(handle);
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    session.onTerminalPtyResize(100, 30);
    expect(handle.resizeCalls, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(handle.resizeCalls, contains((30, 100)));
  });
}
