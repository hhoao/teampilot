@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

/// Fake process echoing argv back on stdout once, then exiting 17.
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

/// Fake process that echoes every stdin chunk back on stdout and stays open
/// until killed, for observing a channel across a mid-session rekey.
class _EchoingProcess implements SSHServerProcess {
  final _stdin = StreamController<List<int>>();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _exit = Completer<int>();

  _EchoingProcess() {
    _stdin.stream.listen((data) => _stdout.add(Uint8List.fromList(data)));
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    if (!_exit.isCompleted) _exit.complete(9);
  }

  @override
  StreamSink<List<int>> get stdin => _stdin.sink;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;
}

void main() {
  test('six failed auth attempts disconnect the client', () async {
    var failures = 0;
    final (server, client) = await startRawPair(
      authenticate: (_) async => false,
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Userauth_Failure.messageId) {
          failures += 1;
        }
        return true;
      },
      onReady: (client) {
        client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
        // Keep the failed attempts coming until the server cuts the
        // connection; a server without a throttle would answer all twenty.
        for (var i = 0; i < 20; i++) {
          try {
            client.sendPacket(testProbeRequest().encode());
          } on Object {
            break; // the transport is already gone
          }
        }
      },
    );
    // The connection died...
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      throwsA(anything),
    );
    await waitUntil(() => server.activeConnections == 0);
    // ...after at most six failed attempts were answered along the way.
    expect(failures, lessThanOrEqualTo(6));
    await server.close();
    client.close();
  });

  test('one crashing connection does not kill the listener', () async {
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
        processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
      ),
    );

    // A raw client that speaks a version banner and then pure garbage — not
    // even a key exchange.
    final (garbageSocket, garbageServerSocket) = loopbackSSHSocketPair();
    connections.add(garbageServerSocket);
    await waitUntil(() => server.activeConnections == 1);
    garbageSocket.sink.add(utf8.encode('SSH-2.0-Garbage\r\n'));
    // A packet length of 0xffffffff: unparseable, over every bound.
    garbageSocket.sink.add(Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0x01]));

    // The server closes that connection off...
    await waitUntil(() => server.activeConnections == 0);
    await garbageSocket.done;

    // ...and the listener is unharmed: a fresh, honest connection still
    // authenticates and execs on the same server.
    final (clientSocket, goodServerSocket) = loopbackSSHSocketPair();
    connections.add(goodServerSocket);
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
      identities: [testDeviceKey],
    );
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['still', 'alive'])),
    );
    expect(await utf8.decoder.bind(session.stdout).join(), 'still alive');

    await client.close();
    await server.close();
    await connections.close();
  });

  test('five concurrent connections all authenticate and exec', () async {
    Future<void> oneRound(int index) async {
      final (client, server) = await startDualPair(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
        processFactory: (argv, cwd, env) async => _EchoProcess(argv)..start(),
      );
      final session = await client.execute(
        TpExecCodec.encode(SSHExecRequest(argv: ['round', '$index'])),
      );
      expect(await utf8.decoder.bind(session.stdout).join(), 'round $index');
      client.close();
      await server.close();
    }

    // Five sequential socket pairs driven in parallel futures: every one of
    // them must authenticate and exec independently.
    await Future.wait([for (var i = 0; i < 5; i++) oneRound(i)]);
  });

  test('rekey mid-session keeps the channel alive', () async {
    final process = _EchoingProcess();
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      processFactory: (argv, cwd, env) async => process,
    );
    final session = await client.execute(
      TpExecCodec.encode(const SSHExecRequest(argv: ['cat'])),
    );
    final output = StreamIterator(utf8.decoder.bind(session.stdout));

    session.stdin.add(Uint8List.fromList(utf8.encode('before')));
    expect(await output.moveNext(), isTrue);
    expect(output.current, 'before');

    // Force a client-side rekey mid-session through the fork's public
    // SSHClient.rekey() API: the exchange runs over the live channel, and
    // the channel must keep working on the new keys.
    await client.rekey();

    session.stdin.add(Uint8List.fromList(utf8.encode('after')));
    expect(await output.moveNext(), isTrue);
    expect(output.current, 'after');
    expect(client.isClosed, isFalse);

    await output.cancel();
    client.close();
    await server.close();
  });
}
