import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartssh2/dartssh2.dart' show SSHKeyPair, OpenSSHEd25519KeyPair;
import 'package:pinenacl/ed25519.dart' as ed25519;

import '../io/filesystem.dart';

/// The embedded server's host key and its OpenSSH-style SHA256 fingerprint.
class EmbeddedHostKey {
  const EmbeddedHostKey({required this.keyPair, required this.fingerprint});

  final SSHKeyPair keyPair;

  /// `SHA256:<base64-no-padding>` of the public-key wire blob — the format
  /// offer `hostKeyFingerprints` already filters for.
  final String fingerprint;
}

/// Load-or-generate the desktop's embedded-server host key, persisted as an
/// unencrypted OpenSSH PEM at `connect/host_key`.
class EmbeddedHostKeyStore {
  EmbeddedHostKeyStore({required this.fs, required this.appDataRoot});

  final Filesystem fs;
  final String appDataRoot;

  String get keyPath => fs.pathContext.join(appDataRoot, 'connect', 'host_key');

  Future<EmbeddedHostKey> loadOrCreate() async {
    final existing = await _loadExisting();
    if (existing != null) return existing;
    return _generateAndPersist();
  }

  Future<EmbeddedHostKey?> _loadExisting() async {
    final pem = await fs.readString(keyPath);
    if (pem == null || pem.trim().isEmpty) return null;
    try {
      final keyPair = SSHKeyPair.fromPem(pem).single;
      if (keyPair.type != 'ssh-ed25519') return null;
      return EmbeddedHostKey(
        keyPair: keyPair,
        fingerprint: _fingerprintOf(keyPair),
      );
    } on Object {
      // Corrupt file: regenerate (spec's error-handling table). The next
      // phone connect fails the pin check and surfaces the re-pair hint.
      return null;
    }
  }

  Future<EmbeddedHostKey> _generateAndPersist() async {
    final signingKey = ed25519.SigningKey.generate();
    final keyPair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(signingKey.publicKey.asTypedList),
      // The full 64-byte secret (seed || public) — the OpenSSH wire layout.
      Uint8List.fromList(signingKey.asTypedList),
      'teampilot-embedded-host',
    );
    await fs.ensureDir(fs.pathContext.dirname(keyPath));
    await fs.atomicWrite(keyPath, keyPair.toPem());
    return EmbeddedHostKey(
      keyPair: keyPair,
      fingerprint: _fingerprintOf(keyPair),
    );
  }

  static String _fingerprintOf(SSHKeyPair keyPair) {
    final bytes = keyPair.toPublicKey().encode();
    return 'SHA256:'
        '${base64.encode(crypto.sha256.convert(bytes).bytes).replaceAll('=', '')}';
  }
}
