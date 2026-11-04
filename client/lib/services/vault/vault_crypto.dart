import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pointycastle/export.dart';

import '../../models/vault_document.dart';
import 'vault_errors.dart';

class VaultEnvelope {
  const VaultEnvelope({
    required this.version,
    required this.salt,
    required this.nonce,
    required this.payload,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  factory VaultEnvelope.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != 1) {
      throw const VaultFormatException('unsupported envelope version');
    }
    final kdf = json['kdf'];
    final cipher = json['cipher'];
    if (kdf is! Map || cipher is! Map) {
      throw const VaultFormatException('missing kdf/cipher');
    }
    try {
      return VaultEnvelope(
        version: 1,
        salt: base64Decode(kdf['salt'] as String),
        nonce: base64Decode(cipher['nonce'] as String),
        payload: base64Decode(json['payload'] as String),
        memoryKiB: (kdf['memoryKiB'] as num).toInt(),
        iterations: (kdf['iterations'] as num).toInt(),
        parallelism: (kdf['parallelism'] as num).toInt(),
      );
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException('malformed envelope');
    }
  }

  final int version;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object?> toJson() => {
    'v': version,
    'kdf': {
      'name': 'argon2id',
      'salt': base64Encode(salt),
      'memoryKiB': memoryKiB,
      'iterations': iterations,
      'parallelism': parallelism,
    },
    'cipher': {'name': 'aes-256-gcm', 'nonce': base64Encode(nonce)},
    'payload': base64Encode(payload),
  };

  @override
  bool operator ==(Object other) {
    const bytes = ListEquality<int>();
    return other is VaultEnvelope &&
        other.version == version &&
        bytes.equals(other.salt, salt) &&
        bytes.equals(other.nonce, nonce) &&
        bytes.equals(other.payload, payload) &&
        other.memoryKiB == memoryKiB &&
        other.iterations == iterations &&
        other.parallelism == parallelism;
  }

  @override
  int get hashCode {
    const bytes = ListEquality<int>();
    return Object.hash(
      version,
      bytes.hash(salt),
      bytes.hash(nonce),
      bytes.hash(payload),
      memoryKiB,
      iterations,
      parallelism,
    );
  }
}

class VaultCrypto {
  const VaultCrypto({
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 1,
  });

  static const _keyLength = 32;
  static const _saltLength = 16;
  static const _nonceLength = 12;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Fresh random salt for a new vault envelope.
  static Uint8List newSalt() => _randomBytes(_saltLength);

  /// Derives the vault key once; callers cache it for the unlocked session so
  /// saves do not re-run Argon2id on every write.
  Future<Uint8List> deriveKey(String passphrase, Uint8List salt) {
    return Isolate.run(
      () => _deriveKey(
        passphrase: passphrase,
        salt: salt,
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
      ),
    );
  }

  Future<VaultEnvelope> encryptWithKey(
    VaultDocument document,
    Uint8List key,
    Uint8List salt,
  ) async {
    final nonce = _randomBytes(_nonceLength);
    final plaintext = jsonEncode(document.toJson());
    final payload = await Isolate.run(
      () => _encryptWithKeySync(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
      ),
    );
    return VaultEnvelope(
      version: 1,
      salt: salt,
      nonce: nonce,
      payload: payload,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  Future<VaultDocument> decryptWithKey(
    VaultEnvelope envelope,
    Uint8List key,
  ) async {
    final plaintext = await Isolate.run(
      () => _decryptWithKeySync(
        payload: envelope.payload,
        key: key,
        nonce: envelope.nonce,
      ),
    );
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException('decrypted payload is not a vault');
    }
  }

  Future<VaultEnvelope> encrypt(
    VaultDocument document,
    String passphrase,
  ) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final plaintext = jsonEncode(document.toJson());
    final payload = await Isolate.run(
      () => _encryptSync(
        plaintext: plaintext,
        passphrase: passphrase,
        salt: salt,
        nonce: nonce,
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
      ),
    );
    return VaultEnvelope(
      version: 1,
      salt: salt,
      nonce: nonce,
      payload: payload,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  Future<VaultDocument> decrypt(
    VaultEnvelope envelope,
    String passphrase,
  ) async {
    final plaintext = await Isolate.run(
      () => _decryptSync(
        payload: envelope.payload,
        passphrase: passphrase,
        salt: envelope.salt,
        nonce: envelope.nonce,
        memoryKiB: envelope.memoryKiB,
        iterations: envelope.iterations,
        parallelism: envelope.parallelism,
      ),
    );
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException('decrypted payload is not a vault');
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

Uint8List _encryptWithKeySync({
  required String plaintext,
  required Uint8List key,
  required Uint8List nonce,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  return cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
}

String _decryptWithKeySync({
  required Uint8List payload,
  required Uint8List key,
  required Uint8List nonce,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  try {
    return utf8.decode(cipher.process(payload));
  } on Object {
    throw const VaultDecryptException();
  }
}

Uint8List _encryptSync({
  required String plaintext,
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final key = _deriveKey(
    passphrase: passphrase,
    salt: salt,
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  return cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
}

String _decryptSync({
  required Uint8List payload,
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final key = _deriveKey(
    passphrase: passphrase,
    salt: salt,
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  try {
    return utf8.decode(cipher.process(payload));
  } on Object {
    // GCM tag mismatch 与结构损坏不可区分；都不泄露任何明文。
    throw const VaultDecryptException();
  }
}

Uint8List _deriveKey({
  required String passphrase,
  required Uint8List salt,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: VaultCrypto._keyLength,
        iterations: iterations,
        memory: memoryKiB,
        lanes: parallelism,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(passphrase)));
}
