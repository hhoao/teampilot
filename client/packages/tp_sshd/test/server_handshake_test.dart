@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

/// Fake process echoing argv back on stdout (server_exec_test's shape).
class _EchoProcess implements SSHServerProcess {
  _EchoProcess(this.argv);

  final List<String> argv;
  final _stdout = StreamController<Uint8List>();

  @override
  Future<int> get exitCode async => 17;

  @override
  void kill() {}

  @override
  StreamSink<List<int>> get stdin => const StreamSinkStub();

  @override
  Stream<Uint8List> get stderr => const Stream.empty();

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  void start() {
    _stdout.add(Uint8List.fromList(utf8.encode(argv.join(' '))));
    _stdout.close();
  }
}

class StreamSinkStub implements StreamSink<List<int>> {
  const StreamSinkStub();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}

void main() {
  test('client handshake reaches auth and fails closed without userauth',
      () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => false,
      ),
    );
    connections.add(serverSocket);
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
    );
    // No identities, and the server has no userauth service yet: the
    // connection must terminate with an auth failure, not hang or crash.
    // (dartssh2's auth errors implement SSHAuthError, not dart:core's
    // Exception, so that is what a clean failure looks like here.)
    await expectLater(
      client.authenticated,
      throwsA(isA<SSHAuthError>()),
    );
    expect(server.activeConnections, greaterThanOrEqualTo(0));
    await server.close();
  });

  test('auth timeout closes silent connections', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => false,
        authTimeout: const Duration(milliseconds: 150),
      ),
    );
    connections.add(serverSocket);
    // Client transport that never sends a service request after kex.
    final transport = SSHTransport(clientSocket);
    await expectLater(
      transport.done.timeout(const Duration(seconds: 2)),
      completes,
    );
    await server.close();
    transport.close();
  });

  test('a connection-stream error is contained and tears down live connections',
      () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
      ),
    );
    // One good connection is live when the accept source dies mid-stream.
    connections.add(serverSocket);
    await waitUntil(() => server.activeConnections == 1);

    connections.addError(StateError('accept source broke'));

    // The stream's error surfaces on done — instead of escaping as an
    // unhandled zone error that would take the embedding app down — and the
    // live connection does not survive a dead listener.
    await expectLater(server.done, throwsA(isA<StateError>()));
    await waitUntil(() => server.activeConnections == 0);
    // The torn-down connection closed its socket: the client end of the
    // in-memory pair saw the shutdown.
    await clientSocket.done;

    await connections.close();
    await server.close();
  });

  test('aes256-gcm is negotiated and carries login + exec end to end',
      () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
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
    connections.add(serverSocket);
    // The client offers only aes256-gcm, so the handshake can only succeed
    // by negotiating it in both directions (the server advertises
    // chacha20-poly1305 and aes256-gcm) — this pins the FFI cipher swap's
    // path through the real kex, NEWKEYS, and channel traffic.
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
      identities: [testDeviceKey],
      algorithms: const SSHAlgorithms(
        cipher: [SSHCipherType.aes256gcm],
      ),
    );
    await client.authenticated;
    final session = await client.execute(
      TpExecCodec.encode(
        const SSHExecRequest(argv: ['claude', '--version']),
      ),
    );
    final output = await utf8.decoder.bind(session.stdout).join();
    expect(output, 'claude --version');
    expect(await session.waitForExit(), 17);
    client.close();
    await connections.close();
    await server.close();
  });
}
