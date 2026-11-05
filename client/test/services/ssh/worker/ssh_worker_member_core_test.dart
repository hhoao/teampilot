import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_exec_pump.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_pty_pump.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

void main() {
  test('exec output is visible before the command exits', () async {
    final session = _FakeWorkerExecSession();
    final events = <SshWorkerEvent>[];
    final pump = SshWorkerExecPump(
      id: 'member-1/exec-1',
      session: session,
      sendEvent: events.add,
      onFinished: () {},
    );
    pump.start();

    session.stdoutController.add(Uint8List.fromList([1, 2]));
    await Future<void>.delayed(Duration.zero);

    expect(events.single.stream, SshWorkerExecStream.stdout);
    expect(events.single.bytes, [1, 2]);
    var completed = false;
    unawaited(pump.done.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    session.finish(exitCode: 0);
    await pump.done;
  });

  test('killing an exec sends SSH KILL to the remote session', () async {
    final session = _FakeWorkerExecSession();
    final pump = SshWorkerExecPump(
      id: 'member-1/exec-1',
      session: session,
      sendEvent: (_) {},
      onFinished: () {},
    );
    pump.start();

    pump.kill();

    expect(session.killedSignal, SSHSignal.KILL);
    session.finish(exitCode: 137);
    await pump.done;
  });

  test('exec pump writes stdin and closes it', () async {
    final session = _FakeWorkerExecSession();
    final pump = SshWorkerExecPump(
      id: 'member-1/exec-1',
      session: session,
      sendEvent: (_) {},
      onFinished: () {},
    );
    pump.start();

    pump.write(Uint8List.fromList([1, 2, 3]));
    pump.closeStdin();

    expect(session.written, [1, 2, 3]);
    expect(session.stdinClosed, isTrue);
    session.finish(exitCode: 0);
    await pump.done;
  });

  test('exec EOF drains within the ACK window', () async {
    final session = _FakeWorkerExecSession();
    final events = <SshWorkerEvent>[];
    final pump = SshWorkerExecPump(
      id: 'member-1/exec-1',
      session: session,
      sendEvent: events.add,
      onFinished: () {},
      outputWindow: 1,
    );
    pump.start();

    session.stdoutController.add(Uint8List.fromList([1]));
    session.stdoutController.add(Uint8List.fromList([2]));
    session.finish(exitCode: 0);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));

    pump.acknowledge(0);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(2));
    pump.acknowledge(1);
    await pump.done;

    expect(events.map((event) => event.bytes), [
      [1],
      [2],
      isEmpty,
    ]);
    expect(events.last.isFinal, isTrue);
  });

  test('streaming exec forwards long output without a capture limit', () async {
    final session = _FakeWorkerExecSession();
    final events = <SshWorkerEvent>[];
    final pump = SshWorkerExecPump(
      id: 'member-1/exec-1',
      session: session,
      sendEvent: events.add,
      onFinished: () {},
    );
    pump.start();

    session.stdoutController.add(Uint8List(sshWorkerMaxExecOutput + 1));
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .where((event) => !event.isFinal!)
          .fold<int>(0, (total, event) => total + event.bytes!.length),
      sshWorkerMaxExecOutput + 1,
    );
    expect(session.killedSignal, isNull);
    session.finish(exitCode: 0);
    await pump.done;
  });

  test(
    'EOF drain stays within ACK window and preserves final ordering',
    () async {
      final session = _FakeWorkerPtySession();
      final events = <SshWorkerEvent>[];
      var finishedCount = 0;
      final pump = SshWorkerPtyPump(
        id: 'member-1/pty-1',
        memberId: 'member-1',
        session: session,
        sendEvent: events.add,
        onFinished: () => finishedCount++,
        outputWindow: 1,
      );
      pump.start();

      session.stdoutController.add(Uint8List(64 * 1024));
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));

      session.stdoutController.add(Uint8List.fromList([7, 8, 9]));
      final stdoutClosed = session.stdoutController.close();
      final stderrClosed = session.stderrController.close();
      session.finish(exitCode: 23);

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      pump.acknowledge(0);

      await pump.done.timeout(const Duration(milliseconds: 100));
      await Future.wait([stdoutClosed, stderrClosed]);

      expect(events.where((event) => event.isFinal == true), hasLength(1));
      expect(events[events.length - 2].bytes, [7, 8, 9]);
      expect(events.last.exitCode, 23);
      expect(finishedCount, 1);
    },
  );
}

final class _FakeWorkerExecSession implements SshWorkerExecSession {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final _done = Completer<void>();
  int? _exitCode;
  SSHSignal? killedSignal;
  final written = <int>[];
  var stdinClosed = false;

  @override
  Stream<Uint8List> get stdout => stdoutController.stream;

  @override
  Stream<Uint8List> get stderr => stderrController.stream;

  @override
  Future<void> get done => _done.future;

  @override
  int? get exitCode => _exitCode;

  @override
  void write(Uint8List data) => written.addAll(data);

  @override
  void closeStdin() => stdinClosed = true;

  @override
  void kill(SSHSignal signal) => killedSignal = signal;

  @override
  void close() => finish(exitCode: _exitCode ?? 0);

  void finish({required int exitCode}) {
    _exitCode = exitCode;
    if (!_done.isCompleted) _done.complete();
    unawaited(stdoutController.close());
    unawaited(stderrController.close());
  }
}

final class _FakeWorkerPtySession implements SshWorkerPtySession {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final _done = Completer<void>();
  int? _exitCode;

  @override
  Stream<Uint8List> get stdout => stdoutController.stream;

  @override
  Stream<Uint8List> get stderr => stderrController.stream;

  @override
  Future<void> get done => _done.future;

  @override
  int? get exitCode => _exitCode;

  @override
  void close() {
    finish(exitCode: _exitCode ?? 0);
  }

  void finish({required int exitCode}) {
    _exitCode = exitCode;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}
