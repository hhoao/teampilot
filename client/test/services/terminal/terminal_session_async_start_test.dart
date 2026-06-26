import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  final doneCompleter = Completer<int>();
  var closed = false;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  void close() {
    closed = true;
    if (!doneCompleter.isCompleted) {
      doneCompleter.complete(0);
    }
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

void main() {
  test(
    'remote sessions skip local executable and working directory validation',
    () async {
      final transport = _FakeTransport();
      var started = false;
      final session = TerminalSession(
        executable: 'flashskyai',
        validateLaunch: false,
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
              return Future.value(transport);
            },
      );
      addTearDown(session.dispose);

      session.connect(workingDirectory: '/remote/path/that/is/not/local');
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 220));

      expect(started, isTrue);
      expect(session.isRunning, isTrue);
    },
  );

  test(
    'dispose during async transport start closes late transport',
    () async {
      final transport = _FakeTransport();
      final starter = Completer<TerminalTransport>();
      final session = TerminalSession(
        executable: '/bin/echo',
        validateLaunch: false,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              return starter.future;
            },
      );
      addTearDown(session.dispose);

      session.connect(workingDirectory: '/tmp');
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 220));

      session.disconnect();
      starter.complete(transport);
      await Future<void>.delayed(Duration.zero);

      expect(transport.closed, isTrue);
      expect(session.isRunning, isFalse);
    },
  );

  test('connect after dispose is a no-op', () async {
    final session = TerminalSession(
      executable: '/bin/echo',
      validateLaunch: false,
    );
    session.dispose();
    session.connect(workingDirectory: '/tmp');
    session.onViewportResize(80, 24);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(session.isRunning, isFalse);
    expect(session.isDisposed, isTrue);
  });

  test('dispose during async transport start does not touch engine grid', () async {
    final transport = _FakeTransport();
    final starter = Completer<TerminalTransport>();
    final session = TerminalSession(
      executable: '/bin/echo',
      validateLaunch: false,
      transportStarter:
          (
            executable, {
            required arguments,
            required workingDirectory,
            required columns,
            required rows,
            environment,
          }) {
            return starter.future;
          },
    );

    session.connect(workingDirectory: '/tmp');
    session.onViewportResize(80, 24);
    await Future<void>.delayed(Duration.zero);

    session.dispose();
    starter.complete(transport);
    await Future<void>.delayed(Duration.zero);

    expect(transport.closed, isTrue);
    expect(session.isDisposed, isTrue);
  });
}
