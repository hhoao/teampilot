import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
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
}) async {
  final (clientSocket, serverSocket) = loopbackSSHSocketPair();
  final connections = StreamController<SSHSocket>();
  final server = await SSHServer.bind(
    StreamIterator(connections.stream),
    config: SSHServerConfig(
      hostKeyPair: hostKeyPair,
      expectedUsername: username,
      authenticate: authenticate,
    ),
  );
  connections.add(serverSocket);
  final client = SSHClient(
    clientSocket,
    username: username,
    onVerifyHostKey: (_, __) => true,
    identities: clientIdentities,
  );
  await client.authenticated; // throws on auth failure — callers rely on that
  return (client, server);
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
