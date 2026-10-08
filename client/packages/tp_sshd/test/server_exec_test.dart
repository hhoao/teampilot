@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHDisconnectError;
import 'package:dartssh2/protocol.dart';
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
  Future<void> addStream(Stream<List<int>> stream) =>
      Future<void>.error(StateError('stdin is gone'));

  @override
  Future<void> close() => Future.value();

  @override
  Future<void> get done => Future.value();
}

/// A process whose stdin sink accepts nothing: every `addStream` waits on a
/// gate the test controls, standing in for a program that never reads its
/// stdin (C05's `sleep 30`).
class _NeverReadingProcess implements SSHServerProcess {
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
  StreamSink<List<int>> get stdin => _NeverReadingStdinSink();

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void finish() {
    _stdout.close();
    _stderr.close();
    if (!_exit.isCompleted) _exit.complete(0);
  }
}

class _NeverReadingStdinSink implements StreamSink<List<int>> {
  final _gate = Completer<void>();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => _gate.future;

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

  test('plain shell-string exec runs through the configured shell factory',
      () async {
    final commands = <String>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
      shellExecFactory: (command, env) async {
        commands.add(command);
        return _EchoProcess(['echo', command])..start();
      },
    );
    final session = await client.execute('command -v claude');
    final output = await utf8.decoder.bind(session.stdout).join();
    expect(commands, ['command -v claude']);
    expect(output, 'echo command -v claude');
    expect(await session.waitForExit(), 17);
    client.close();
    await server.close();
  });

  test('plain shell-string exec without a shell factory is refused', () async {
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
    );
    await expectLater(
      client.execute('rm -rf /'), // no tp1: prefix, no shell factory
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

  test('a process that never reads stdin keeps the granted window a bound',
      () async {
    // F4's session half (C05): against a program that never reads stdin,
    // bytes the program has not taken are never re-granted, so the client's
    // granted window is a real bound — a peer that keeps sending past it
    // beyond sshd's 10% grace margin is disconnected instead of buffered
    // unboundedly.
    final process = _NeverReadingProcess();
    final opened = Completer<void>();
    final execAccepted = Completer<void>();
    final adjusts = <int>[];
    final (connection, client) = await startRawAuthenticatedConnection(
      processFactory: (argv, cwd, env) async => process,
      onServerMessage: (payload) {
        switch (SSHMessage.readMessageId(payload)) {
          case SSH_Message_Channel_Confirmation.messageId:
            if (!opened.isCompleted) opened.complete();
          case SSH_Message_Channel_Success.messageId:
            if (!execAccepted.isCompleted) execAccepted.complete();
          case SSH_Message_Channel_Window_Adjust.messageId:
            adjusts.add(
              SSH_Message_Channel_Window_Adjust.decode(payload).bytesToAdd,
            );
        }
      },
    );
    addTearDown(connection.close);
    addTearDown(client.close);

    client.sendPacket(
      SSH_Message_Channel_Open.session(
        senderChannel: 100,
        initialWindowSize: 2 * 1024 * 1024,
        maximumPacketSize: 32768,
      ).encode(),
    );
    await opened.future;
    final serverChannel = connection.channels.keys.single;
    client.sendPacket(
      SSH_Message_Channel_Request.exec(
        recipientChannel: serverChannel,
        wantReply: true,
        command: TpExecCodec.encode(const SSHExecRequest(argv: ['sleep'])),
      ).encode(),
    );
    await execAccepted.future;

    // 64 chunks of 32768 spend the 2 MiB window; the seventh overflowing
    // chunk crosses the 10% grace and draws the disconnect.
    final chunk = Uint8List(32768);
    for (var i = 0; i < 71; i++) {
      client.sendPacket(
        SSH_Message_Channel_Data(
          recipientChannel: serverChannel,
          data: chunk,
        ).encode(),
      );
    }
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      throwsA(
        isA<SSHDisconnectError>()
            .having((error) => error.reasonCode, 'reasonCode', 2)
            .having(
              (error) => error.message,
              'message',
              'channel $serverChannel: peer ignored channel window',
            ),
      ),
    );
    // The stdin gate never opened, so nothing was ever re-granted.
    expect(adjusts, isEmpty);
    process.finish();
  });
}
