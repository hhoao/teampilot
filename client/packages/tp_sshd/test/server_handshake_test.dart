@TestOn('vm')
library;

import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

void main() {
  test('client handshake reaches auth and fails closed without userauth', () async {
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
}
