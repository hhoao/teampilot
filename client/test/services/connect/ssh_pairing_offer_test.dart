import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

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
      tlsCertSha256: 'deadbeef',
    ),
    relay: relay,
  );
}

void main() {
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
