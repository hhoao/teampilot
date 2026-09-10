@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

void main() {
  test('valid device key authenticates', () async {
    var authenticateCalls = 0;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (req) async {
        authenticateCalls += 1;
        expect(req.username, 'user');
        expect(req.algorithm, 'ssh-ed25519');
        expect(req.publicKey, testDeviceKey.toPublicKey().encode());
        return true;
      },
      clientIdentities: [testDeviceKey],
    );
    // In-memory key pairs sign directly (no probing), so the embedder is
    // consulted exactly once, for the signed request.
    expect(authenticateCalls, 1);
    expect(server.activeConnections, 1);
    await server.close();
    await client.close();
  });

  test('probed device key is answered with PK_Ok and then authenticates',
      () async {
    var authenticateCalls = 0;
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async {
        authenticateCalls += 1;
        return true;
      },
      clientIdentities: [
        SSHIdentity.custom(
          type: 'ssh-ed25519',
          publicKey: testDeviceKey.toPublicKey(),
          signer: testDeviceKey.sign,
          shouldProbe: true,
        ),
      ],
    );
    // The probe and the signed request each consult authenticate.
    expect(authenticateCalls, 2);
    expect(server.activeConnections, 1);
    await server.close();
    await client.close();
  });

  test('untrusted key is rejected', () async {
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
      identities: [testDeviceKey],
    );
    await expectLater(client.authenticated, throwsA(isA<SSHAuthError>()));
    await server.close();
    await client.close();
  });

  test('server enforces the signature, not just key trust', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        // The key itself would be trusted...
        authenticate: (_) async => true,
      ),
    );
    connections.add(serverSocket);
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
      identities: [
        SSHIdentity.custom(
          type: 'ssh-ed25519',
          publicKey: testDeviceKey.toPublicKey(),
          // ...but the client signs with a well-formed ssh-ed25519
          // signature frame whose 64 bytes do not verify. authenticate()
          // returning true must not be enough to authenticate.
          signer: (_) => SSHEd25519Signature(Uint8List(64)),
        ),
      ],
    );
    await expectLater(client.authenticated, throwsA(isA<SSHAuthError>()));
    await server.close();
    await client.close();
  });

  test('wrong username counts as a failed attempt', () async {
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
    connections.add(serverSocket);
    final client = SSHClient(
      clientSocket,
      username: 'mallory',
      onVerifyHostKey: (_, __) => true,
      identities: [testDeviceKey],
    );
    // The key is valid and trusted, but the connection was offered to
    // 'user', not 'mallory' — the request must be failed, not accepted.
    await expectLater(client.authenticated, throwsA(isA<SSHAuthError>()));
    await server.close();
    await client.close();
  });

  test('auth timer does not fire after successful authentication', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connections = StreamController<SSHSocket>();
    final server = await SSHServer.bind(
      StreamIterator(connections.stream),
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
        authTimeout: const Duration(milliseconds: 150),
      ),
    );
    connections.add(serverSocket);
    final client = SSHClient(
      clientSocket,
      username: 'user',
      onVerifyHostKey: (_, __) => true,
      identities: [testDeviceKey],
    );
    await client.authenticated;
    // The auth timeout must have been cancelled by the success, not merely
    // survived by the phase guard: the connection stays up well past it.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(server.activeConnections, 1);
    expect(client.isClosed, isFalse);
    await server.close();
    await client.close();
  });

  test('malformed userauth message disconnects the connection', () async {
    final (server, client) = await startRawPair(
      authenticate: (_) async => true,
      onReady: (client) {
        client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
        // Hand-encoded publickey probe whose public key blob is truncated:
        // the string length prefix promises 32 bytes, but the packet ends
        // after only 10 of them.
        final writer = SSHMessageWriter();
        writer.writeUint8(SSH_Message_Userauth_Request.messageId);
        writer.writeUtf8('user');
        writer.writeUtf8('ssh-connection');
        writer.writeUtf8('publickey');
        writer.writeBool(false);
        writer.writeUtf8('ssh-ed25519');
        writer.writeString(Uint8List(32));
        final bytes = writer.takeBytes();
        client.sendPacket(
          Uint8List.sublistView(bytes, 0, bytes.length - 10),
        );
      },
    );
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      throwsA(
        isA<SSHDisconnectError>().having(
          (error) => error.reasonCode,
          'reasonCode',
          2, // SSH_DISCONNECT_PROTOCOL_ERROR
        ),
      ),
    );
    await server.close();
    client.close();
  });

  test('too many failed attempts disconnects the connection', () async {
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
        // Six probes of an untrusted key: the default maxAuthAttempts.
        for (var i = 0; i < 6; i++) {
          client.sendPacket(testProbeRequest().encode());
        }
      },
    );
    await expectLater(
      client.done.timeout(const Duration(seconds: 5)),
      throwsA(
        isA<SSHDisconnectError>().having(
          (error) => error.reasonCode,
          'reasonCode',
          14, // SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE
        ),
      ),
    );
    // The first five attempts were answered with a failure; the sixth is
    // answered with the disconnect above instead.
    expect(failures, 5);
    await server.close();
    client.close();
  });
}
