import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'authorized_keys_file.dart';
import 'pairing_token_gate.dart';

class PairingPostBody {
  const PairingPostBody({
    required this.token,
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
  });

  final String token;
  final String deviceId;
  final String deviceName;
  final String publicKey;
}

class PairingPostResult {
  const PairingPostResult({
    required this.ok,
    required this.profileHint,
    this.relayGrant,
  });

  final bool ok;
  final String profileHint;
  final String? relayGrant;
}

class PairingHttpException implements Exception {
  const PairingHttpException(this.code);

  final String code;

  @override
  String toString() => 'PairingHttpException($code)';
}

Future<PairingPostResult> handlePairingPost({
  required PairingPostBody body,
  required PairingTokenGate gate,
  required AuthorizedKeysFile keys,
  required DateTime now,
  required String profileHint,
  String? relayGrant,
}) async {
  if (!_isEd25519PublicKey(body.publicKey)) {
    throw const PairingHttpException('badKey');
  }
  if (!gate.consume(body.token, now)) {
    throw PairingHttpException(gate.hasActiveToken ? 'used' : 'invalid');
  }
  try {
    await keys.upsertDevice(
      publicKey: body.publicKey,
      deviceId: body.deviceId,
      deviceName: body.deviceName,
    );
  } on ArgumentError {
    throw const PairingHttpException('invalid');
  }
  return PairingPostResult(
    ok: true,
    profileHint: profileHint,
    relayGrant: relayGrant,
  );
}

class PairingTlsPin {
  const PairingTlsPin._();

  static bool matches({
    required List<int> derBytes,
    required String expectedSha256Hex,
  }) {
    final expected = expectedSha256Hex.toLowerCase();
    final actual = sha256.convert(derBytes).toString().toLowerCase();
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index++) {
      difference |= actual.codeUnitAt(index) ^ expected.codeUnitAt(index);
    }
    return difference == 0;
  }
}

bool _isEd25519PublicKey(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length < 2 || parts.length > 3 || parts.first != 'ssh-ed25519') {
    return false;
  }
  try {
    base64.decode(base64.normalize(parts[1]));
    return true;
  } on FormatException {
    return false;
  }
}
