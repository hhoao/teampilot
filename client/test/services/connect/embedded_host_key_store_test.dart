@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/embedded_host_key_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  EmbeddedHostKeyStore newStore() =>
      EmbeddedHostKeyStore(fs: fs, appDataRoot: '/data');

  test('generates on first load and persists for the second', () async {
    final store = newStore();
    final first = await store.loadOrCreate();
    expect(first.fingerprint, startsWith('SHA256:'));
    expect(first.keyPair.type, 'ssh-ed25519');

    final second = await newStore().loadOrCreate();
    expect(second.fingerprint, first.fingerprint);
  });

  test('fingerprint is the SHA256 of the public key wire blob', () async {
    final key = await newStore().loadOrCreate();
    final blob = key.keyPair.toPublicKey().encode();
    final expected =
        'SHA256:${base64.encode(sha256.convert(blob).bytes).replaceAll('=', '')}';
    expect(key.fingerprint, expected);
  });

  test('corrupt key file is regenerated, not fatal', () async {
    final path = fs.pathContext.join('/data', 'connect', 'host_key');
    await fs.ensureDir(fs.pathContext.dirname(path));
    await fs.writeString(path, 'not a pem');
    final key = await newStore().loadOrCreate();
    expect(key.fingerprint, isNotEmpty);
  });
}
