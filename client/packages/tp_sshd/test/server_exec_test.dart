@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';

/// Fake process echoing argv back on stdout with a configurable exit code.
class _EchoProcess implements SSHServerProcess {
  _EchoProcess(this.argv);

  final List<String> argv;
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();

  @override
  Future<int> get exitCode async => 17;

  @override
  void kill() {}

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void start() {
    _stdout.add(Uint8List.fromList(utf8.encode(argv.join(' '))));
    _stdout.close();
    _stderr.close();
  }
}

/// Fake process whose `exitCode` completes with an error instead of a code:
/// a broken process contract, not a process that exited.
class _ExplodingExitProcess implements SSHServerProcess {
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _exit = Completer<int>();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    // Safe after the contract already broke, like after a real exit.
    if (!_exit.isCompleted) _exit.complete(9);
  }

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void start() {
    _stdout.add(Uint8List.fromList(utf8.encode('partial output')));
    _stdout.close();
    _stderr.close();
  }

  /// Breaks the process contract: exitCode completes with an error from
  /// here on. Called by the test once the pipes are wired, so the failure
  /// deterministically lands on a live pipe.
  void breakContract() {
    if (!_exit.isCompleted) {
      _exit.completeError(StateError('process contract broke'));
    }
  }
}

/// Fake process whose stdin sink throws on every write.
class _ThrowingStdinProcess implements SSHServerProcess {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _exit = Completer<int>();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(9);
  }

  @override
  StreamSink<List<int>> get stdin => _ThrowingStdinSink();

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void finish(int code) {
    _stdout.close();
    _stderr.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

/// A stdin sink that is already gone: every write throws.
class _ThrowingStdinSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) => throw StateError('stdin is gone');

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => Future.value();

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();
}

void main() {
  test('structured exec spawns argv and reports exit code', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async {
        expect(cwd, 'C:\\work\\demo');
        expect(env['TEAMPilot_TEST'], '1');
        final process = _EchoProcess(argv)..start();
        return process;
      },
    );
    final session = await client.execute(
      TpExecCodec.encode(
        const SSHExecRequest(
          argv: ['claude', '--version'],
          cwd: r'C:\work\demo',
          env: {'TEAMPilot_TEST': '1'},
        ),
      ),
    );
    final output = await utf8.decoder.bind(session.stdout).join();
    expect(output, 'claude --version');
    // waitForExit is the fork's public API for the exit status; the raw
    // getter only reflects what has already been reported.
    expect(await session.waitForExit(), 17);
    client.close();
    await server.close();
  });

  test('plain shell-string exec is rejected', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
    );
    await expectLater(
      client.execute('rm -rf /'), // no tp1: prefix
      throwsA(anything),
    );
    client.close();
    await server.close();
  });

  test('host-info query is answered without spawning', () async {
    var factoryCalled = false;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      hostInfo: () => const SSHHostInfo(
        platform: 'windows',
        osUser: 'dev',
        elevated: false,
        inDocker: false,
        shell: 'powershell',
      ),
      processFactory: (argv, cwd, env) async {
        factoryCalled = true;
        return _EchoProcess(argv)..start();
      },
    );
    final session = await client.execute(TpExecCodec.encodeHostInfoQuery());
    final raw = await utf8.decoder.bind(session.stdout).join();
    final info = SSHHostInfo.fromJson(raw);
    expect(info.platform, 'windows');
    expect(factoryCalled, isFalse);
    client.close();
    await server.close();
  });

  test('a process whose exitCode errors finishes the channel fail-safe',
      () async {
    final process = _ExplodingExitProcess()..start();
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
    );
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['broken'])),
    );
    // Whatever output the process produced is delivered first...
    final output = StreamIterator(utf8.decoder.bind(session.stdout));
    expect(await output.moveNext(), isTrue);
    expect(output.current, 'partial output');
    await output.cancel();
    // ...then its exitCode contract breaks. The channel finishes instead of
    // hanging on a future that errored, and no exit status is invented for a
    // process that never exited.
    process.breakContract();
    await session.done.timeout(const Duration(seconds: 5));
    expect(await session.waitForExit(), isNull);
    // The broken process took its channel, not the connection.
    expect(client.isClosed, isFalse);

    client.close();
    await server.close();
  });

  test('a process stdin that throws on write is treated as input-side close',
      () async {
    final process = _ThrowingStdinProcess();
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
    );
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['picky'])),
    );
    // Input hits a stdin contract that throws on every write: the throw is
    // contained (it must not escape as an unhandled error and kill the
    // connection)...
    session.stdin.add(Uint8List.fromList(utf8.encode('hello')));
    session.stdin.add(Uint8List.fromList(utf8.encode('again')));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(client.isClosed, isFalse);

    // ...and the channel still finishes normally when the process exits.
    process.finish(0);
    expect(await session.waitForExit(), 0);
    await session.done.timeout(const Duration(seconds: 5));

    client.close();
    await server.close();
  });
}
