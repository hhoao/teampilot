// VM-only: reaches the client's private session-channel opener through
// dart:mirrors, like the fork's own channel-open tests do.
library;

import 'dart:async';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/protocol.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'test_socket_pair.dart';

/// Starts an [SSHServer] over a fresh in-memory socket pair and returns a
/// connected, host-key-accepting [SSHClient] plus the server.
///
/// The client authenticates as [username] with [clientIdentities]; the server
/// decides each attempt through [authenticate], which must accept [username]
/// as [SSHServerConfig.expectedUsername].
Future<(SSHClient, SSHServer)> startDualPair({
  required SSHKeyPair hostKeyPair,
  required Future<bool> Function(SSHServerAuthRequest request) authenticate,
  List<SSHIdentity> clientIdentities = const [],
  String username = 'user',
  SSHProcessFactory? processFactory,
  SSHPtyFactory? ptyFactory,
  SSHHostInfo Function()? hostInfo,
  SftpFileSystem? sftpFileSystem,
  SSHBindServerSocket? bindServerSocket,
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connections = StreamController<SSHSocket>();
  final server = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKeyPair,
      expectedUsername: username,
      authenticate: authenticate,
      processFactory: processFactory,
      ptyFactory: ptyFactory,
      hostInfo: hostInfo,
      sftpFileSystem: sftpFileSystem,
      bindServerSocket: bindServerSocket,
    ),
  );
  connections.add(serverSocket);
  final client = _connectClient(
    clientSocket,
    username: username,
    identities: clientIdentities,
  );
  await client.authenticated; // throws on auth failure — callers rely on that
  return (client, server);
}

/// Starts a single [SSHServerConnection] over a fresh in-memory socket pair
/// and returns it with a connected, authenticated client.
///
/// Like [startDualPair], but hands the test the connection object itself, so
/// it can reach the server-side channel table through
/// [SSHServerConnection.channels].
Future<(SSHClient, SSHServerConnection)> startDualConnection({
  required SSHKeyPair hostKeyPair,
  required Future<bool> Function(SSHServerAuthRequest request) authenticate,
  List<SSHIdentity> clientIdentities = const [],
  String username = 'user',
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connection = SSHServerConnection(
    serverSocket,
    config: SSHServerConfig(
      hostKeyPair: hostKeyPair,
      expectedUsername: username,
      authenticate: authenticate,
    ),
  );
  final client = _connectClient(
    clientSocket,
    username: username,
    identities: clientIdentities,
  );
  await client.authenticated;
  return (client, connection);
}

SSHClient _connectClient(
  SSHSocket socket, {
  required String username,
  required List<SSHIdentity> identities,
}) {
  return SSHClient(
    socket,
    username: username,
    onVerifyHostKey: (_, __) => true,
    identities: identities,
  );
}

/// Starts a single [SSHServerConnection] plus a raw client-side
/// [SSHTransport] that authenticates with the test device key.
///
/// Like [startDualConnection], but the client is a bare transport driving
/// the protocol by hand, so tests can inject channel traffic a real
/// [SSHClient] would never produce (tiny windows, hand-crafted packets).
/// [onServerMessage] sees every message the server sends back (consumed by
/// default). The returned future completes once the server has accepted the
/// authentication.
Future<(SSHServerConnection, SSHTransport)> startRawAuthenticatedConnection({
  void Function(Uint8List payload)? onServerMessage,
  SSHBindServerSocket? bindServerSocket,
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connection = SSHServerConnection(
    serverSocket,
    config: SSHServerConfig(
      hostKeyPair: testHostKey,
      expectedUsername: 'user',
      authenticate: (_) async => true,
      bindServerSocket: bindServerSocket,
    ),
  );
  final authenticated = Completer<void>();
  final publicKey = testDeviceKey.toPublicKey().encode();
  late final SSHTransport client;
  client = SSHTransport(
    clientSocket,
    onVerifyHostKey: (_, __) => true,
    onReady: () {
      client.sendPacket(SSH_Message_Service_Request('ssh-userauth').encode());
      // The RFC 4252 §7 signed request: the challenge is the session-id
      // prefixed request-without-signature, exactly what the server
      // re-composes to verify.
      final challenge = client.composeChallenge(
        username: 'user',
        service: 'ssh-connection',
        publicKeyAlgorithm: 'ssh-ed25519',
        publicKey: publicKey,
      );
      final signature = testDeviceKey.sign(challenge);
      client.sendPacket(
        SSH_Message_Userauth_Request.publicKey(
          username: 'user',
          publicKeyAlgorithm: 'ssh-ed25519',
          publicKey: publicKey,
          signature: signature.encode(),
        ).encode(),
      );
    },
    onMessage: (payload) {
      if (SSHMessage.readMessageId(payload) ==
              SSH_Message_Userauth_Success.messageId &&
          !authenticated.isCompleted) {
        authenticated.complete();
      }
      onServerMessage?.call(payload);
      return true;
    },
  );
  await authenticated.future.timeout(const Duration(seconds: 10));
  return (connection, client);
}

/// A probing publickey userauth request (RFC 4252 §7, `boolean FALSE`) for
/// the test device key: a well-formed attempt that never verifies as
/// trusted, for driving the auth-failure path.
SSH_Message_Userauth_Request testProbeRequest() {
  return SSH_Message_Userauth_Request.publicKey(
    username: 'user',
    publicKeyAlgorithm: 'ssh-ed25519',
    publicKey: testDeviceKey.toPublicKey().encode(),
    signature: null,
  );
}

/// Starts an [SSHServer] plus a raw client-side [SSHTransport], so tests can
/// inject hand-crafted traffic a real [SSHClient] would never send.
///
/// [onReady] runs once the client-side key exchange completes;
/// [onServerMessage] sees everything the server sends back (consumed by
/// default).
Future<(SSHServer, SSHTransport)> startRawPair({
  required Future<bool> Function(SSHServerAuthRequest request) authenticate,
  required void Function(SSHTransport client) onReady,
  bool Function(Uint8List payload)? onServerMessage,
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connections = StreamController<SSHSocket>();
  final server = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: testHostKey,
      expectedUsername: 'user',
      authenticate: authenticate,
    ),
  );
  connections.add(serverSocket);
  late final SSHTransport client;
  client = SSHTransport(
    clientSocket,
    onVerifyHostKey: (_, __) => true,
    onReady: () => onReady(client),
    onMessage: onServerMessage ?? (_) => true,
  );
  return (server, client);
}

/// Polls [condition] every 5 ms until it holds, or fails after [timeout].
///
/// For awaiting delivery over the in-memory socket pair, where the only
/// observable state is on one side of the pair.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within $timeout', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Opens a session channel on [client] and completes with its controller.
///
/// dartssh2 exposes no public channel-open-by-type API: `execute`/`shell`
/// open a session channel but then block on the request reply, which the
/// tp_sshd server does not answer until Tasks 6-7. The fork's own tests
/// reach the same private opener through mirrors
/// (`test/src/ssh_client_channel_open_test.dart`), so this harness mirrors
/// that (VM-only) pattern.
Future<SSHChannelController> openClientSessionChannel(SSHClient client) {
  final library = reflectClass(SSHClient).owner as LibraryMirror;
  final symbol = MirrorSystem.getSymbol('_openSessionChannel', library);
  return reflect(client).invoke(symbol, const []).reflectee
      as Future<SSHChannelController>;
}

/// Throwaway ed25519 host key generated for these tests only
/// (ssh-keygen -t ed25519 -N '' -C 'tp-sshd-task3-throwaway-host').
const _testHostKeyPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBaO+vVZtKIrnAOvc/nSZjaP3FEP93i4OaShgxSseqQVQAAAKDJb4G9yW+B
vQAAAAtzc2gtZWQyNTUxOQAAACBaO+vVZtKIrnAOvc/nSZjaP3FEP93i4OaShgxSseqQVQ
AAAEBbwZXXKRuEXWx0OerUp/Iw3p2CxVjtI3A+1kfLHnq9x1o769Vm0oiucA69z+dJmNo/
cUQ/3eLg5pKGDFKx6pBVAAAAHHRwLXNzaGQtdGFzazMtdGhyb3dhd2F5LWhvc3QB
-----END OPENSSH PRIVATE KEY-----
''';

/// Throwaway ed25519 device key generated for these tests only
/// (ssh-keygen -t ed25519 -N '' -C 'tp-sshd-task3-throwaway-device').
/// Stands in for the client's signing identity in the dual tests.
const _testDeviceKeyPem = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBfOUUkbEjlCib02adS9nooS27BojdzCrQLvojmh3SKNgAAAKjuDLL17gyy
9QAAAAtzc2gtZWQyNTUxOQAAACBfOUUkbEjlCib02adS9nooS27BojdzCrQLvojmh3SKNg
AAAEDK4vf00uW/7iMbnSbwIEkGtQhz7S6tUatX0XoF7G69j185RSRsSOUKJvTZp1L2eihL
bsGiN3MKtAu+iOaHdIo2AAAAHnRwLXNzaGQtdGFzazMtdGhyb3dhd2F5LWRldmljZQECAw
QFBgc=
-----END OPENSSH PRIVATE KEY-----
''';

/// A throwaway ed25519 keypair for tests (public key in OpenSSH wire format
/// via `.toPublicKey().encode()`).
final testHostKey = SSHKeyPair.fromPem(_testHostKeyPem).single;

/// A throwaway ed25519 keypair used as a client identity for tests.
final testDeviceKey = SSHKeyPair.fromPem(_testDeviceKeyPem).single;
