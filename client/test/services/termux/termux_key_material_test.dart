import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/termux/termux_key_material.dart';

void main() {
  group('TermuxKeyMaterial', () {
    test('ensureKeyPair writes files and saves credential', () async {
      final native = await Directory.systemTemp.createTemp('termux_key_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      final credentials = InMemorySshCredentialStore();
      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: native.path,
        credentials: credentials,
      );

      final privateKeyPath = TermuxKeyMaterial.privateKeyPath(native.path);
      final publicKeyPath = TermuxKeyMaterial.publicKeyPath(native.path);
      expect(await File(privateKeyPath).exists(), isTrue);
      expect(await File(publicKeyPath).exists(), isTrue);
      expect(await File(privateKeyPath).readAsString(), isNotEmpty);
      expect(await File(publicKeyPath).readAsString(), isNotEmpty);

      final stored = await credentials.loadPrivateKey('termux');
      expect(stored, isNotEmpty);
      expect(
        stored,
        await File(privateKeyPath).readAsString(),
      );
    });

    test('ensureKeyPair PEM round-trips through SSHKeyPair.fromPem', () async {
      final native = await Directory.systemTemp.createTemp('termux_pem_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: native.path,
        credentials: InMemorySshCredentialStore(),
      );

      final pem = await File(
        TermuxKeyMaterial.privateKeyPath(native.path),
      ).readAsString();
      expect(() => SSHKeyPair.fromPem(pem), returnsNormally);
      expect(SSHKeyPair.fromPem(pem), isNotEmpty);
    });

    test('ensureKeyPair syncs credential from existing private key file', () async {
      final native = await Directory.systemTemp.createTemp('termux_sync_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      final credentials = InMemorySshCredentialStore();
      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: native.path,
        credentials: credentials,
      );
      final pem = await credentials.loadPrivateKey('termux');
      expect(pem, isNotEmpty);

      final emptyCreds = InMemorySshCredentialStore();
      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: native.path,
        credentials: emptyCreds,
      );

      expect(await emptyCreds.loadPrivateKey('termux'), pem);
    });

    test('publicKeyOpenSsh returns ssh-ed25519 line', () async {
      final native = await Directory.systemTemp.createTemp('termux_pub_');
      addTearDown(() async {
        if (await native.exists()) await native.delete(recursive: true);
      });

      await TermuxKeyMaterial.ensureKeyPair(
        nativeAppDataPath: native.path,
        credentials: InMemorySshCredentialStore(),
      );

      final line = await TermuxKeyMaterial.publicKeyOpenSsh(native.path);
      expect(line, startsWith('ssh-ed25519 '));
    });
  });
}
