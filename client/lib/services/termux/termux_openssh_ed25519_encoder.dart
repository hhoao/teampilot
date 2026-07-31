import 'dart:convert';
import 'dart:math';

import 'package:pinenacl/ed25519.dart';

/// Generates OpenSSH-format ed25519 key material for Termux loopback auth.
class TermuxOpenSshEd25519Encoder {
  const TermuxOpenSshEd25519Encoder();

  TermuxEd25519KeyPair generate({String comment = 'teampilot-termux'}) {
    final signingKey = SigningKey.generate();
    final seed = Uint8List.fromList(signingKey.seed.asTypedList);
    final pubBytes = Uint8List.fromList(signingKey.publicKey.asTypedList);
    return TermuxEd25519KeyPair(
      privateKeyPem: _buildPrivateKeyPem(
        pubBytes: pubBytes,
        seedBytes: seed,
        comment: comment,
      ),
      publicKeyOpenSsh: _buildPublicKeyOpenSsh(
        pubBytes: pubBytes,
        comment: comment,
      ),
    );
  }

  String _buildPublicKeyOpenSsh({
    required Uint8List pubBytes,
    required String comment,
  }) {
    final buf = BytesBuilder();
    _writeString(buf, 'ssh-ed25519');
    _writeBytes(buf, pubBytes);
    final b64 = base64.encode(buf.toBytes());
    return 'ssh-ed25519 $b64 $comment'.trim();
  }

  String _buildPrivateKeyPem({
    required Uint8List pubBytes,
    required Uint8List seedBytes,
    required String comment,
  }) {
    final privBytes = Uint8List(64)
      ..setRange(0, 32, seedBytes)
      ..setRange(32, 64, pubBytes);

    final pubBlob = _buildPubBlob(pubBytes);
    final privBlob = _buildPrivBlob(pubBytes, privBytes, comment);

    final outer = BytesBuilder();
    outer.add(utf8.encode('openssh-key-v1\x00'));
    _writeString(outer, 'none');
    _writeString(outer, 'none');
    _writeString(outer, '');
    _writeUint32(outer, 1);
    _writeBytes(outer, pubBlob);
    _writeBytes(outer, privBlob);

    final b64 = base64.encode(outer.toBytes());
    final lines = RegExp('.{1,70}')
        .allMatches(b64)
        .map((m) => m.group(0)!)
        .join('\n');
    return '-----BEGIN OPENSSH PRIVATE KEY-----\n$lines\n-----END OPENSSH PRIVATE KEY-----\n';
  }

  Uint8List _buildPubBlob(Uint8List pubBytes) {
    final b = BytesBuilder();
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    return b.toBytes();
  }

  Uint8List _buildPrivBlob(
    Uint8List pubBytes,
    Uint8List privBytes,
    String comment,
  ) {
    final checkInt = Random.secure().nextInt(0xFFFFFFFF);
    final b = BytesBuilder();
    _writeUint32(b, checkInt);
    _writeUint32(b, checkInt);
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    _writeBytes(b, privBytes);
    _writeString(b, comment);
    var pad = 1;
    while (b.length % 8 != 0) {
      b.addByte(pad++);
    }
    return b.toBytes();
  }

  void _writeUint32(BytesBuilder b, int value) {
    b.addByte((value >> 24) & 0xFF);
    b.addByte((value >> 16) & 0xFF);
    b.addByte((value >> 8) & 0xFF);
    b.addByte(value & 0xFF);
  }

  void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }

  void _writeBytes(BytesBuilder b, Uint8List bytes) {
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }
}

class TermuxEd25519KeyPair {
  const TermuxEd25519KeyPair({
    required this.privateKeyPem,
    required this.publicKeyOpenSsh,
  });

  final String privateKeyPem;
  final String publicKeyOpenSsh;
}
