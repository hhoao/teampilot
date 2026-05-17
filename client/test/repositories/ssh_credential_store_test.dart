import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';

class _FakeSecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test(
    'secure SSH credential store keeps sensitive fields in secure backend',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureSshCredentialStore(backend);

      await store.savePassword('p1', 'secret');
      await store.savePrivateKey('p1', 'PRIVATE KEY');
      await store.savePrivateKeyPassphrase('p1', 'phrase');

      expect(await store.loadPassword('p1'), 'secret');
      expect(await store.loadPrivateKey('p1'), 'PRIVATE KEY');
      expect(await store.loadPrivateKeyPassphrase('p1'), 'phrase');
      expect(
        backend.values.keys,
        contains('flashskyai.ssh_creds.v1.p1.password'),
      );
    },
  );

  test(
    'secure SSH credential store deletes all fields for a profile',
    () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureSshCredentialStore(backend);

      await store.savePassword('p1', 'secret');
      await store.savePrivateKey('p1', 'PRIVATE KEY');
      await store.savePrivateKeyPassphrase('p1', 'phrase');
      await store.deleteAll('p1');

      expect(await store.loadPassword('p1'), isNull);
      expect(await store.loadPrivateKey('p1'), isNull);
      expect(await store.loadPrivateKeyPassphrase('p1'), isNull);
    },
  );
}
