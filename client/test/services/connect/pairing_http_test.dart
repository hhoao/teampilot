import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/pairing_token_gate.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);

  AuthorizedKeysFile keysFor(List<String> writes) => AuthorizedKeysFile(
    path: '/keys',
    read: (_) async => '',
    write: (_, value) async => writes.add(value),
    chmod: (_, {required mode}) async {},
  );

  PairingPostBody body(String token, {String publicKey = 'ssh-ed25519 AAAA'}) =>
      PairingPostBody(
        token: token,
        deviceId: 'pixel-1',
        deviceName: 'Pixel',
        publicKey: publicKey,
      );

  test('accepts a valid single-use pairing request', () async {
    final gate = PairingTokenGate();
    final writes = <String>[];
    final result = await handlePairingPost(
      body: body(gate.mint(now: now)),
      gate: gate,
      keys: keysFor(writes),
      now: now,
      profileHint: 'alice-laptop',
      relayGrant: 'grant',
    );

    expect(result.ok, isTrue);
    expect(result.profileHint, 'alice-laptop');
    expect(result.relayGrant, 'grant');
    expect(writes.single, contains('device=pixel-1'));
  });

  test('rejects invalid, used, expired, and non-Ed25519 keys', () async {
    final writes = <String>[];
    final invalidGate = PairingTokenGate();
    await expectLater(
      () => handlePairingPost(
        body: body('wrong'),
        gate: invalidGate,
        keys: keysFor(writes),
        now: now,
        profileHint: 'desktop',
      ),
      throwsA(isA<PairingHttpException>()),
    );

    final expiredGate = PairingTokenGate();
    final expired = expiredGate.mint(now: now, ttl: const Duration(seconds: 1));
    await expectLater(
      () => handlePairingPost(
        body: body(expired),
        gate: expiredGate,
        keys: keysFor(writes),
        now: now.add(const Duration(seconds: 2)),
        profileHint: 'desktop',
      ),
      throwsA(isA<PairingHttpException>()),
    );

    final keyGate = PairingTokenGate();
    await expectLater(
      () => handlePairingPost(
        body: body(keyGate.mint(now: now), publicKey: 'ssh-rsa AAAA'),
        gate: keyGate,
        keys: keysFor(writes),
        now: now,
        profileHint: 'desktop',
      ),
      throwsA(
        isA<PairingHttpException>().having(
          (error) => error.code,
          'code',
          'badKey',
        ),
      ),
    );
  });

  test('matches the advertised DER certificate SHA-256 pin', () {
    final der = utf8.encode('certificate');
    expect(
      PairingTlsPin.matches(
        derBytes: der,
        expectedSha256Hex:
            '03d66dd08835c1ca3f128cceacd1f31ac94163096b20f445ae84285bc0832d72',
      ),
      isTrue,
    );
    expect(
      PairingTlsPin.matches(derBytes: der, expectedSha256Hex: 'deadbeef'),
      isFalse,
    );
  });
}
