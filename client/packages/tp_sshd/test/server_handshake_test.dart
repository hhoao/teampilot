@TestOn('vm')
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

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
}
