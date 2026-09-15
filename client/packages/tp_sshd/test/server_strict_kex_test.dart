@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' show SSHHandshakeError;
import 'package:dartssh2/protocol.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'test_socket_pair.dart';

/// F2 (A19): a strict-kex violation — a non-KEX packet between KEXINIT and
/// NEWKEYS under negotiated strict kex (RFC 9142 §3.2) — must be answered
/// with a wire DISCONNECT(2, "strict KEX violation: …") before the
/// connection closes, the way sshd does, instead of a bare TCP close.
///
/// The whole exchange is hand-driven in the clear: the violation happens
/// during the initial key exchange, so no NEWKEYS has been applied and
/// every packet — including the DISCONNECT under test — is plaintext.
void main() {
  test('a mid-KEX packet under strict kex draws a wire DISCONNECT', () async {
    final (clientSocket, serverSocket) = loopbackSSHSocketPair();
    final connection = SSHServerConnection(
      serverSocket,
      config: SSHServerConfig(
        hostKeyPair: testHostKey,
        expectedUsername: 'user',
        authenticate: (_) async => true,
      ),
    );

    final received = BytesBuilder();
    final disconnectSeen = Completer<SSH_Message_Disconnect>();
    late final StreamSubscription<Uint8List> subscription;
    subscription = clientSocket.stream.listen((data) {
      received.add(data);
      final disconnect = _scanForDisconnect(received.toBytes());
      if (disconnect != null && !disconnectSeen.isCompleted) {
        disconnectSeen.complete(disconnect);
      }
    });

    // The client side of the handshake, by hand: version banner, then a
    // KEXINIT advertising strict kex (the kex-strict-c-v00@openssh.com
    // pseudo-algorithm), then the violation itself — a SERVICE_REQUEST
    // between KEXINIT and NEWKEYS (A19's stimulus).
    clientSocket.sink.add(utf8Encode('SSH-2.0-DartSSH_2.0\r\n'));
    clientSocket.sink.add(_plainPacket(_strictKexClientKexInit().encode()));
    clientSocket.sink.add(
      _plainPacket(SSH_Message_Service_Request('ssh-userauth').encode()),
    );

    final disconnect = await disconnectSeen.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError(
        'no SSH_MSG_DISCONNECT observed: the connection was torn down '
        'without a wire reason (A19)',
      ),
    );
    await subscription.cancel();

    expect(disconnect.reasonCode, 2); // SSH_DISCONNECT_PROTOCOL_ERROR
    expect(
      disconnect.description.toLowerCase(),
      contains('strict kex violation'),
      reason: 'the description must name the strict-key-exchange violation',
    );

    // The connection still closes — the Terrapin countermeasure itself was
    // already enforced; this fix only makes the reason visible on the wire.
    await expectLater(
      connection.done.timeout(const Duration(seconds: 5)),
      throwsA(isA<SSHHandshakeError>()),
    );
    await connection.close();
    clientSocket.destroy();
  });
}

/// The client KEXINIT A19 sends: x25519 (in tp_sshd's offer) plus the strict
/// kex indicator, and an algorithm set that intersects [tpServerAlgorithms].
SSH_Message_KexInit _strictKexClientKexInit() => SSH_Message_KexInit(
      kexAlgorithms: const [
        'curve25519-sha256',
        'kex-strict-c-v00@openssh.com',
      ],
      serverHostKeyAlgorithms: const ['ssh-ed25519'],
      encryptionClientToServer: const ['chacha20-poly1305@openssh.com'],
      encryptionServerToClient: const ['chacha20-poly1305@openssh.com'],
      macClientToServer: const ['hmac-sha2-256'],
      macServerToClient: const ['hmac-sha2-256'],
      compressionClientToServer: const ['none'],
      compressionServerToClient: const ['none'],
      firstKexPacketFollows: false,
    );

/// Builds an unencrypted SSH packet carrying [payload] (RFC 4253 §6), as it
/// goes on the wire before NEWKEYS.
Uint8List _plainPacket(Uint8List payload) {
  var padding = 4;
  while ((4 + 1 + payload.length + padding) % 8 != 0) {
    padding++;
  }
  final packet = Uint8List(4 + 1 + payload.length + padding);
  ByteData.sublistView(packet, 0, 4)
      .setUint32(0, 1 + payload.length + padding);
  packet[4] = padding;
  packet.setRange(5, 5 + payload.length, payload);
  return packet;
}

/// Scans [bytes] for an SSH_MSG_DISCONNECT packet: skips the version banner
/// line, then walks packet by packet. Returns the first DISCONNECT found, or
/// `null` (also while the buffer still holds an incomplete trailing packet).
SSH_Message_Disconnect? _scanForDisconnect(Uint8List bytes) {
  final bannerEnd = _bannerEnd(bytes);
  if (bannerEnd == null) return null;
  var offset = bannerEnd;
  while (offset + 5 <= bytes.length) {
    final packetLength =
        ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    if (offset + 4 + packetLength > bytes.length) return null;
    final paddingLength = bytes[offset + 4];
    final payload = Uint8List.sublistView(
      bytes,
      offset + 5,
      offset + 4 + packetLength - paddingLength,
    );
    if (SSHMessage.readMessageId(payload) ==
        SSH_Message_Disconnect.messageId) {
      return SSH_Message_Disconnect.decode(payload);
    }
    offset += 4 + packetLength;
  }
  return null;
}

/// The offset just past the `\r\n` of the version banner, or `null` while it
/// has not fully arrived.
int? _bannerEnd(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0d && bytes[i + 1] == 0x0a) return i + 2;
  }
  return null;
}

Uint8List utf8Encode(String s) => Uint8List.fromList(s.codeUnits);
