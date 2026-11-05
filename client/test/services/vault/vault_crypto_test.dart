import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';

const _document = VaultDocument(
  entries: [
    VaultEntry(
      id: '1',
      type: VaultEntryType.apiKey,
      title: 'OpenAI',
      fields: {'apiKey': 'sk-secret'},
    ),
  ],
);

void main() {
  // 低参数只为跑得快；生产默认值另测。
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  test('encrypts and decrypts the document', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    final decoded = await crypto.decrypt(envelope, 'pass');
    expect(decoded, _document);
  });

  test('ciphertext does not contain plaintext', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    expect(utf8.decode(envelope.payload, allowMalformed: true),
        isNot(contains('sk-secret')));
  });

  test('wrong passphrase fails without leaking secrets', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    await expectLater(
      crypto.decrypt(envelope, 'wrong'),
      throwsA(isA<VaultDecryptException>()),
    );
  });

  test('tampered payload fails authentication', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    final payload = Uint8List.fromList(envelope.payload);
    payload[0] ^= 0xff;
    final tampered = VaultEnvelope(
      version: envelope.version,
      salt: envelope.salt,
      nonce: envelope.nonce,
      payload: payload,
      memoryKiB: envelope.memoryKiB,
      iterations: envelope.iterations,
      parallelism: envelope.parallelism,
    );
    await expectLater(
      crypto.decrypt(tampered, 'pass'),
      throwsA(isA<VaultDecryptException>()),
    );
  });

  test('envelope json round-trips and rejects unknown versions', () {
    // 同步构造一个信封只为验证编解码。
    final envelope = VaultEnvelope(
      version: 1,
      salt: Uint8List.fromList(List.filled(16, 1)),
      nonce: Uint8List.fromList(List.filled(12, 2)),
      payload: Uint8List.fromList([1, 2, 3]),
      memoryKiB: 1024,
      iterations: 2,
      parallelism: 1,
    );
    expect(VaultEnvelope.fromJson(envelope.toJson()), envelope);
    expect(
      () => VaultEnvelope.fromJson({...envelope.toJson(), 'v': 2}),
      throwsA(isA<VaultFormatException>()),
    );
  });
}
