import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';

import '../termux/termux_openssh_ed25519_encoder.dart';

/// The phone-install key used to authenticate against paired desktops.
class SshDeviceKey {
  const SshDeviceKey._();

  static ({String pem, String openSshPublic}) generate() {
    final keyPair = const TermuxOpenSshEd25519Encoder().generate(
      comment: 'teampilot-connect',
    );
    return (
      pem: keyPair.privateKeyPem,
      openSshPublic: keyPair.publicKeyOpenSsh,
    );
  }

  /// Stable install id sent with pairing POSTs and relay dials: a digest of
  /// the device public key, so the desktop can tag authorized_keys lines and
  /// scope relay grants without ever seeing another identifier.
  static String deviceIdFor(String openSshPublic) {
    final digest = sha256.convert(utf8.encode(openSshPublic));
    return base64Url
        .encode(digest.bytes.take(12).toList(growable: false))
        .replaceAll('=', '');
  }

  /// Derives [deviceIdFor] material from the stored PEM private key.
  static String deviceIdFromPem(String pem) {
    final pairs = SSHKeyPair.fromPem(pem);
    if (pairs.length != 1 || pairs.single.name != 'ssh-ed25519') {
      throw const FormatException('device key must be one Ed25519 key');
    }
    final encoded = pairs.single.toPublicKey().encode();
    return deviceIdFor('ssh-ed25519 ${base64.encode(encoded)}');
  }
}
