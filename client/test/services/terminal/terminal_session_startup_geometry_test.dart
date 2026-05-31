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

void main() {
  // Regression: the embedding view reports its real cell grid through
  // [TerminalSession.onViewportResize] at the end of the mount frame, which
  // runs BEFORE the deferred (Timer(0)) body of `_startTransport`. The bug:
  // that body called `engine.initializeEmpty(24, 80)`, clobbering the grid the
  // view had just sized, and the post-spawn reconciliation resized only the
  // PTY — never the engine. The mirror grid was then stuck at 24 rows inside a
  // taller viewport, so new output rendered into the top rows with dead space
  // below and the view could not reach the live bottom until a window resize
  // re-fired `onViewportResize`.
  test('engine grid adopts viewport geometry reported before spawn', () async {
    final handle = _FakeTransport();
    final session = TerminalSession(
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
    addTearDown(() async {
      session.dispose();
      await handle.outputController.close();
    });

    session.connect(workingDirectory: Directory.systemTemp.path);
    // Lands in the same turn, before the deferred _startTransport body — the
    // ordering the real app hits on every launch (post-frame ahead of Timer(0)).
    session.onViewportResize(120, 40);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await flushTerminalEngine(session.engine);

    // The mirror grid must match the real viewport, not the 80x24 placeholder.
    expect(session.engine.grid.rows, 40);
    expect(session.engine.grid.columns, 120);
    // And the PTY was reconciled to the same geometry after attach.
    expect(handle.resizeCalls, contains((40, 120)));
  });
}
