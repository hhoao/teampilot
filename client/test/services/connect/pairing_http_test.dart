import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/pairing_token_gate.dart';

void main() {
  final now = DateTime.utc(2026, 8, 25, 12);

  PairingPostBody body(String token, {String publicKey = 'ssh-ed25519 AAAA'}) =>
      PairingPostBody(
        token: token,
        deviceId: 'pixel-1',
        deviceName: 'Pixel',
        publicKey: publicKey,
      );

  test('accepts a valid single-use pairing request', () async {
    final gate = PairingTokenGate();
    final accepted = <Map<String, String>>[];
    final result = await handlePairingPost(
      body: body(gate.mint(now: now)),
      gate: gate,
      acceptDevice:
          ({
            required String deviceId,
            required String deviceName,
            required String publicKey,
          }) async {
            accepted.add({
              'deviceId': deviceId,
              'deviceName': deviceName,
              'publicKey': publicKey,
            });
          },
      now: now,
      profileHint: 'alice-laptop',
      relayGrant: 'grant',
    );

    expect(result.ok, isTrue);
    expect(result.profileHint, 'alice-laptop');
    expect(result.relayGrant, 'grant');
    expect(accepted, [
      {
        'deviceId': 'pixel-1',
        'deviceName': 'Pixel',
        'publicKey': 'ssh-ed25519 AAAA',
      },
    ]);
  });

  test('rejects invalid, used, expired, and non-Ed25519 keys', () async {
    final accepted = <Map<String, String>>[];
    Future<void> sink({
      required String deviceId,
      required String deviceName,
      required String publicKey,
    }) async {
      accepted.add({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKey,
      });
    }

    final invalidGate = PairingTokenGate();
    await expectLater(
      () => handlePairingPost(
        body: body('wrong'),
        gate: invalidGate,
        acceptDevice: sink,
        now: now,
        profileHint: 'desktop',
      ),
      throwsA(
        isA<PairingHttpException>().having(
          (error) => error.code,
          'code',
          'invalid',
        ),
      ),
    );

    final expiredGate = PairingTokenGate();
    final expired = expiredGate.mint(now: now, ttl: const Duration(seconds: 1));
    await expectLater(
      () => handlePairingPost(
        body: body(expired),
        gate: expiredGate,
        acceptDevice: sink,
        now: now.add(const Duration(seconds: 2)),
        profileHint: 'desktop',
      ),
      throwsA(
        isA<PairingHttpException>().having(
          (error) => error.code,
          'code',
          'used',
        ),
      ),
    );

    final keyGate = PairingTokenGate();
    await expectLater(
      () => handlePairingPost(
        body: body(keyGate.mint(now: now), publicKey: 'ssh-rsa AAAA'),
        gate: keyGate,
        acceptDevice: sink,
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

    expect(accepted, isEmpty);
  });

  test('a device sink rejection surfaces as invalid', () async {
    final gate = PairingTokenGate();
    await expectLater(
      () => handlePairingPost(
        body: body(gate.mint(now: now)),
        gate: gate,
        acceptDevice:
            ({
              required String deviceId,
              required String deviceName,
              required String publicKey,
            }) async {
              throw ArgumentError.value(deviceId, 'deviceId');
            },
        now: now,
        profileHint: 'desktop',
      ),
      throwsA(
        isA<PairingHttpException>().having(
          (error) => error.code,
          'code',
          'invalid',
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
