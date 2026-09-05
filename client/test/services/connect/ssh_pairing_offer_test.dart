import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

String base64UrlEncodeNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

SshPairingOffer _offer({SshRelayOffer? relay}) {
  return SshPairingOffer(
    v: 1,
    hostId: 'AbCdEf0123_-xyZ9',
    username: 'alice',
    displayName: 'alice-laptop',
    appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
    endpoints: const [
      SshReachabilityEndpoint(
        kind: SshEndpointKind.lan,
        host: '192.168.1.20',
        port: 22,
      ),
      SshReachabilityEndpoint(
        kind: SshEndpointKind.extra,
        host: '203.0.113.8',
        port: 2222,
      ),
    ],
    hostKeyFingerprints: const ['SHA256:abcdefgh'],
    pairing: const SshPairingSession(
      token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
      expiresAt: 1770000000000,
      url: 'https://192.168.1.20:2768/pair',
      tlsCertSha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    ),
    relay: relay,
  );
}

SshPairingOffer _offerWithRelay() => _offer(
  relay: const SshRelayOffer(
    v: 1,
    url: 'wss://relay.example.test/ws',
    hostId: 'AbCdEf0123_-xyZ9',
    inviteToken: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
    inviteExpiresAt: 1770000000000,
  ),
);

void main() {
  test('bare code round-trips from QR payload', () {
    final offer = _offer();
    expect(SshPairingOffer.decode(offer.bareCode).username, 'alice');
  });

  test('compressed QR payload round-trips and is shorter than bare code', () {
    final offer = _offer(
      relay: const SshRelayOffer(
        v: 1,
        url: 'wss://relay.example.test/ws',
        hostId: 'AbCdEf0123_-xyZ9',
        inviteToken: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
        inviteExpiresAt: 1770000000000,
      ),
    );
    final decoded = SshPairingOffer.decode(offer.qrPayload);
    expect(decoded.username, 'alice');
    expect(decoded.pairing.url, 'https://192.168.1.20:2768/pair');
    expect(decoded.relay?.url, 'wss://relay.example.test/ws');
    expect(offer.qrPayload.startsWith('z'), isTrue);
    expect(offer.qrPayload.length, lessThan(offer.bareCode.length * 0.75));
  });

  test('binary QR bytes round-trip through decodeBytes', () {
    final offer = _offerWithRelay();
    final decoded = SshPairingOffer.decodeBytes(
      Uint8List.fromList(offer.qrBytes),
    );
    expect(decoded.username, 'alice');
    expect(decoded.hostId, 'AbCdEf0123_-xyZ9');
    expect(decoded.appDataRoot, '/home/alice/.local/share/com.hhoa.teampilot');
    expect(
      decoded.endpoints.map((endpoint) => (endpoint.kind, endpoint.port)),
      [
        (SshEndpointKind.lan, 22),
        (SshEndpointKind.extra, 2222),
      ],
    );
    expect(
      decoded.hostKeyFingerprints,
      const ['SHA256:abcdefgh'],
    );
    expect(decoded.pairing.token, offer.pairing.token);
    expect(decoded.pairing.tlsCertSha256, offer.pairing.tlsCertSha256);
    expect(decoded.pairing.url, 'https://192.168.1.20:2768/pair');
    expect(decoded.relay?.url, 'wss://relay.example.test/ws');
  });

  test('binary QR bytes stay small enough for a coarse module grid', () {
    final offer = _offerWithRelay();
    // ~230 bytes fits QR version 10-M (213+ codewords); the legacy string
    // form was ~350 chars in the denser byte-mode grid.
    expect(offer.qrBytes.length, lessThan(260));
    expect(offer.qrBytes.first, 0x7A);
  });

  test('scanner relay string form ("r" prefix) decodes the binary payload', () {
    final offer = _offer();
    final relayed =
        'r${base64UrlEncodeNoPad(Uint8List.fromList(offer.qrBytes))}';
    final decoded = SshPairingOffer.decode(relayed);
    expect(decoded.username, 'alice');
    expect(decoded.pairing.tlsCertSha256, offer.pairing.tlsCertSha256);
  });

  test('decodeBytes falls back to text payloads encoded as UTF-8', () {
    final offer = _offer();
    final decoded = SshPairingOffer.decodeBytes(
      Uint8List.fromList(utf8.encode(offer.qrPayload)),
    );
    expect(decoded.username, 'alice');
    expect(decoded.pairing.url, 'https://192.168.1.20:2768/pair');
    expect(
      SshPairingOffer.decodeBytes(
        Uint8List.fromList(utf8.encode(offer.encode())),
      ).displayName,
      'alice-laptop',
    );
  });

  test('round-trips deep link and bare code', () {
    final encoded = _offer().encode();
    expect(encoded.startsWith('teampilot://pair-ssh?code='), isTrue);
    final fromLink = SshPairingOffer.decode(encoded);
    expect(fromLink.username, 'alice');
    expect(fromLink.hostId, 'AbCdEf0123_-xyZ9');
    expect(fromLink.endpoints.first.host, '192.168.1.20');
    final code = Uri.parse(encoded).queryParameters['code']!;
    expect(SshPairingOffer.decode(code).displayName, 'alice-laptop');
  });

  test('ignores unknown endpoint kinds', () {
    final json = _offer().toJson();
    final endpoints = List<Map<String, Object?>>.from(
      (json['endpoints'] as List).cast<Map<String, Object?>>(),
    );
    endpoints.insert(1, {'kind': 'future', 'host': 'x', 'port': 1});
    json['endpoints'] = endpoints;

    final offer = SshPairingOffer.fromJson(json);

    expect(offer.endpoints.map((e) => e.kind), [
      SshEndpointKind.lan,
      SshEndpointKind.extra,
    ]);
  });

  test('rejects unknown offer version', () {
    final json = _offer().toJson()..['v'] = 2;
    expect(
      () => SshPairingOffer.fromJson(json),
      throwsA(isA<SshPairingOfferFormatException>()),
    );
  });

  test('rejects missing hostId', () {
    final json = _offer().toJson()..remove('hostId');
    expect(
      () => SshPairingOffer.fromJson(json),
      throwsA(isA<SshPairingOfferFormatException>()),
    );
  });

  test('does not serialize passwords or private keys', () {
    final json = _offer().toJson();
    expect(json.containsKey('password'), isFalse);
    expect(json['pairing'], isNot(contains('privateKey')));
  });
}
