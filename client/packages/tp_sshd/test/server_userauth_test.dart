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

  group('USERAUTH_FAILURE advertises the served methods', () {
    /// One raw connection whose service is negotiated and whose stimulus
    /// fires once the userauth phase is reachable; completes with the
    /// methods list of the first USERAUTH_FAILURE the server sends.
    Future<List<String>> firstFailureMethods(
      void Function(SSHTransport client) stimulus, {
      required Future<bool> Function(SSHServerAuthRequest request) authenticate,
    }) async {
      final methods = Completer<List<String>>();
      final (server, client) = await startRawPair(
        authenticate: authenticate,
        onServerMessage: (payload) {
          if (SSHMessage.readMessageId(payload) ==
                  SSH_Message_Userauth_Failure.messageId &&
              !methods.isCompleted) {
            methods.complete(
              SSH_Message_Userauth_Failure.decode(payload).methodsLeft,
            );
          }
          return true;
        },
        onReady: (client) {
          client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
          stimulus(client);
        },
      );
      addTearDown(server.close);
      addTearDown(client.close);
      return methods.future.timeout(const Duration(seconds: 5));
    }

    test('a password-method request is failed with methods=[publickey]',
        () async {
      // A09: the password method is not served, but the failure must still
      // tell the client which method is (RFC 4252 §8) — an empty list reads
      // as "no methods available" and can end a login that would succeed.
      final methods = await firstFailureMethods(
        (client) => client.sendPacket(
          SSH_Message_Userauth_Request.password(
            user: 'user',
            password: 'audit-wrong-password',
          ).encode(),
        ),
        authenticate: (_) async => false,
      );
      expect(methods, ['publickey']);
    });

    test('an undecodable key blob is failed with methods=[publickey]',
        () async {
      // A10: the blob claims 3 name bytes then ends — no key can be read out
      // of it, but the failure answer is the same shape as any other.
      final methods = await firstFailureMethods(
        (client) => client.sendPacket(
          SSH_Message_Userauth_Request.publicKey(
            username: 'user',
            publicKeyAlgorithm: 'ssh-ed25519',
            publicKey: Uint8List.fromList([0, 0, 0, 3, 1, 2, 3]),
            signature: null,
          ).encode(),
        ),
        authenticate: (_) async => false,
      );
      expect(methods, ['publickey']);
    });

    test('a bad signature is failed with methods=[publickey]', () async {
      // A11: the key itself is trusted, but the signed request does not
      // verify — the failure must still advertise publickey.
      final methods = await firstFailureMethods(
        (client) {
          final challenge = client.composeChallenge(
            username: 'user',
            service: 'ssh-connection',
            publicKeyAlgorithm: 'ssh-ed25519',
            publicKey: testDeviceKey.toPublicKey().encode(),
          );
          final corrupted = Uint8List.fromList(challenge);
          corrupted[corrupted.length - 1] ^= 0xff;
          client.sendPacket(
            SSH_Message_Userauth_Request.publicKey(
              username: 'user',
              publicKeyAlgorithm: 'ssh-ed25519',
              publicKey: testDeviceKey.toPublicKey().encode(),
              signature: testDeviceKey.sign(corrupted).encode(),
            ).encode(),
          );
        },
        authenticate: (_) async => true,
      );
      expect(methods, ['publickey']);
    });
  });

  group('no userauth before service negotiation', () {
    test('a userauth request before SERVICE_REQUEST is not processed', () async {
      // A08: sshd only registers the USERAUTH_REQUEST handler once
      // `ssh-userauth` has been accepted, so a probe sent before the
      // service request falls to the default dispatch: UNIMPLEMENTED, and
      // the connection stays open. It must never be answered with
      // USERAUTH_PK_OK or authenticate.
      // The transport answers UNIMPLEMENTED itself (it never reaches
      // onMessage), so the reply is observed through the client transport's
      // trace log — the same recovery the differential raw driver uses.
      final replies = <int>[];
      final settled = Completer<void>();
      final (server, client) = await startRawPair(
        authenticate: (_) async => true,
        onClientTrace: (line) {
          if (line == null) return;
          if (line.contains('<-') &&
              line.contains('SSH_Message_Unimplemented')) {
            replies.add(SSH_Message_Unimplemented.messageId);
            if (!settled.isCompleted) settled.complete();
          }
        },
        onServerMessage: (payload) {
          replies.add(SSHMessage.readMessageId(payload));
          if (!settled.isCompleted) settled.complete();
          return true;
        },
        onReady: (client) {
          // A well-formed publickey probe for the trusted device key —
          // sent before any SERVICE_REQUEST.
          client.sendPacket(testProbeRequest().encode());
        },
      );
      addTearDown(server.close);
      addTearDown(client.close);
      await settled.future.timeout(const Duration(seconds: 5));
      // Give a misbehaving server the chance to answer more than once.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        replies,
        [SSH_Message_Unimplemented.messageId],
        reason: 'a userauth request before the service negotiation must draw '
            'UNIMPLEMENTED, never USERAUTH_PK_OK',
      );
      expect(client.isClosed, isFalse);
    });

    test('the same probe is answered once the service is negotiated', () async {
      // The regression half: the service request path still arms userauth
      // handling, and the identical probe is then answered with PK_OK.
      final replies = <int>[];
      final settled = Completer<void>();
      final (server, client) = await startRawPair(
        authenticate: (_) async => true,
        onServerMessage: (payload) {
          final id = SSHMessage.readMessageId(payload);
          if (id != SSH_Message_Unimplemented.messageId) replies.add(id);
          if (id == SSH_Message_Userauth_PK_Ok.messageId &&
              !settled.isCompleted) {
            settled.complete();
          }
          return true;
        },
        onReady: (client) {
          client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
          client.sendPacket(testProbeRequest().encode());
        },
      );
      addTearDown(server.close);
      addTearDown(client.close);
      await settled.future.timeout(const Duration(seconds: 5));
      expect(replies, [
        SSH_Message_Service_Accept.messageId,
        SSH_Message_Userauth_PK_Ok.messageId,
      ]);
      expect(client.isClosed, isFalse);
    });
  });

  test('onAuthenticated reports the connection and auth request', () async {
    final seen = <(SSHServerConnection, String)>[];
    final (client, server) = await startDualPair(
      hostKeyPair: testHostKey,
      authenticate: (_) async => true,
      clientIdentities: [testDeviceKey],
      onAuthenticated: (connection, request) => seen.add((connection, request.username)),
    );
    await client.authenticated;
    await waitUntil(() => seen.isNotEmpty);
    expect(seen.single.$2, 'user');
    client.close();
    await server.close();
  });

  test('too many failed attempts disconnects the connection', () async {
    var failures = 0;
    final failureMethods = <List<String>>[];
    final (server, client) = await startRawPair(
      authenticate: (_) async => false,
      onServerMessage: (payload) {
        if (SSHMessage.readMessageId(payload) ==
            SSH_Message_Userauth_Failure.messageId) {
          failures += 1;
          // A12: every one of the five answered failures carries the same
          // continuable-methods list (F8) — the cap itself stays reason 14,
          // the documented deliberate divergence from sshd's reason 2.
          failureMethods
              .add(SSH_Message_Userauth_Failure.decode(payload).methodsLeft);
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
    expect(failureMethods, everyElement(['publickey']));
    await server.close();
    client.close();
  });
}
