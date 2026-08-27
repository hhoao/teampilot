import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:posix/posix.dart' as posix;

abstract interface class PairingCertificateProvider {
  Future<PairingCertificate> generate({required String appDataRoot});
}

class PairingCertificate {
  const PairingCertificate({
    required this.tlsContext,
    required this.leafDer,
    required this.certificatePath,
    required this.privateKeyPath,
  });

  final Object tlsContext;
  final List<int> leafDer;
  final String certificatePath;
  final String privateKeyPath;

  String get sha256Hex => sha256.convert(leafDer).toString();
}

/// Generates a fresh one-day self-signed leaf using bundled Dart crypto.
///
/// No executable or platform crypto command is required. The resulting files
/// live under the user-owned application data directory and are restricted to
/// the current user on POSIX hosts.
class ConnectTls implements PairingCertificateProvider {
  ConnectTls({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  @override
  Future<PairingCertificate> generate({required String appDataRoot}) async {
    final material = await Isolate.run(
      () => _generatePairingMaterial(_now().toUtc()),
    );
    final directory = Directory(
      _joinNative(appDataRoot, 'connect', 'certificates'),
    );
    await directory.create(recursive: true);

    final suffix = material.serialHex;
    final certificatePath = _joinNative(directory.path, 'pairing-$suffix.pem');
    final privateKeyPath = _joinNative(directory.path, 'pairing-$suffix.key');
    await _writeOwnerOnly(certificatePath, material.certificatePem);
    try {
      await _writeOwnerOnly(privateKeyPath, material.privateKeyPem);
    } on Object {
      try {
        await File(certificatePath).delete();
      } on Object {
        // Preserve the original private-key write failure.
      }
      rethrow;
    }

    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(material.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(material.privateKeyPem));
    return PairingCertificate(
      tlsContext: context,
      leafDer: material.certificateDer,
      certificatePath: certificatePath,
      privateKeyPath: privateKeyPath,
    );
  }
}

class _PairingCertificateMaterial {
  const _PairingCertificateMaterial({
    required this.certificateDer,
    required this.certificatePem,
    required this.privateKeyPem,
    required this.serialHex,
  });

  final Uint8List certificateDer;
  final String certificatePem;
  final String privateKeyPem;
  final String serialHex;
}

_PairingCertificateMaterial _generatePairingMaterial(DateTime now) {
  final random = Random.secure();
  final secureRandom = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))),
      ),
    );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        secureRandom,
      ),
    );
  final keyPair = generator.generateKeyPair();
  final publicKey = keyPair.publicKey;
  final privateKey = keyPair.privateKey;

  final serialBytes = List<int>.generate(16, (_) => random.nextInt(256));
  serialBytes[0] &= 0x7f;
  if (serialBytes.every((byte) => byte == 0)) serialBytes.last = 1;
  final serialHex = serialBytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  final serial = BigInt.parse(serialHex, radix: 16);

  final signatureAlgorithm = _algorithmIdentifier('1.2.840.113549.1.1.11');
  final name = _commonName('teampilot-pair');
  final tbsCertificate = ASN1Sequence(
    elements: [
      ASN1Object(tag: 0xa0)..valueBytes = ASN1Integer(BigInt.from(2)).encode(),
      ASN1Integer(serial),
      signatureAlgorithm,
      name,
      ASN1Sequence(
        elements: [
          ASN1UtcTime(now.subtract(const Duration(minutes: 5))),
          ASN1UtcTime(now.add(const Duration(days: 1))),
        ],
      ),
      name,
      _subjectPublicKeyInfo(publicKey),
      _leafExtensions(),
    ],
  );
  final tbsDer = tbsCertificate.encode();
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final signature = (signer.generateSignature(tbsDer) as RSASignature).bytes;
  final certificateDer = ASN1Sequence(
    elements: [
      tbsCertificate,
      signatureAlgorithm,
      ASN1BitString(stringValues: signature),
    ],
  ).encode();
  final privateKeyDer = _privateKeyDer(privateKey);

  return _PairingCertificateMaterial(
    certificateDer: certificateDer,
    certificatePem: _pem('CERTIFICATE', certificateDer),
    privateKeyPem: _pem('RSA PRIVATE KEY', privateKeyDer),
    serialHex: serialHex,
  );
}

ASN1Sequence _algorithmIdentifier(String oid) => ASN1Sequence(
  elements: [ASN1ObjectIdentifier.fromIdentifierString(oid), ASN1Null()],
);

ASN1Sequence _commonName(String value) => ASN1Sequence(
  elements: [
    ASN1Set(
      elements: [
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'),
            ASN1PrintableString(stringValue: value),
          ],
        ),
      ],
    ),
  ],
);

ASN1Sequence _subjectPublicKeyInfo(RSAPublicKey key) {
  final publicKeyDer = ASN1Sequence(
    elements: [ASN1Integer(key.modulus), ASN1Integer(key.publicExponent)],
  ).encode();
  return ASN1Sequence(
    elements: [
      _algorithmIdentifier('1.2.840.113549.1.1.1'),
      ASN1BitString(stringValues: publicKeyDer),
    ],
  );
}

ASN1Object _leafExtensions() {
  final basicConstraints = ASN1Sequence(
    elements: [
      ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'),
      ASN1Boolean(true),
      ASN1OctetString(octets: ASN1Sequence().encode()),
    ],
  );
  final extendedKeyUsage = ASN1Sequence(
    elements: [
      ASN1ObjectIdentifier.fromIdentifierString('2.5.29.37'),
      ASN1OctetString(
        octets: ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.5.5.7.3.1'),
          ],
        ).encode(),
      ),
    ],
  );
  return ASN1Object(tag: 0xa3)
    ..valueBytes = ASN1Sequence(
      elements: [basicConstraints, extendedKeyUsage],
    ).encode();
}

Uint8List _privateKeyDer(RSAPrivateKey key) {
  final p = key.p!;
  final q = key.q!;
  final d = key.privateExponent!;
  return ASN1Sequence(
    elements: [
      ASN1Integer(BigInt.zero),
      ASN1Integer(key.modulus),
      ASN1Integer(key.publicExponent),
      ASN1Integer(d),
      ASN1Integer(p),
      ASN1Integer(q),
      ASN1Integer(d % (p - BigInt.one)),
      ASN1Integer(d % (q - BigInt.one)),
      ASN1Integer(q.modInverse(p)),
    ],
  ).encode();
}

String _pem(String label, List<int> der) {
  final encoded = base64.encode(der);
  final lines = <String>[];
  for (var offset = 0; offset < encoded.length; offset += 64) {
    lines.add(encoded.substring(offset, min(offset + 64, encoded.length)));
  }
  return '-----BEGIN $label-----\n${lines.join('\n')}\n'
      '-----END $label-----\n';
}

Future<void> _writeOwnerOnly(String path, String contents) async {
  final file = File(path);
  final handle = await file.open(mode: FileMode.writeOnly);
  try {
    await handle.writeString(contents);
    await handle.flush();
  } finally {
    await handle.close();
  }
  if (!Platform.isWindows) posix.chmod(path, '600');
}

String _joinNative(String first, String second, [String? third]) {
  final separator = Platform.pathSeparator;
  final joined = first.endsWith(separator)
      ? '$first$second'
      : '$first$separator$second';
  return third == null ? joined : '$joined$separator$third';
}
