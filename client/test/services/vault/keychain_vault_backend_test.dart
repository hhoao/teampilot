// client/test/services/vault/keychain_vault_backend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('returns null before the first save', () async {
    final backend = KeychainVaultBackend(_FakeStore());
    expect(await backend.load(), isNull);
    expect(backend.needsUnlock, isFalse);
  });

  test('round-trips the document under one key', () async {
    final store = _FakeStore();
    final backend = KeychainVaultBackend(store);
    const document = VaultDocument(
      entries: [
        VaultEntry(id: '1', type: VaultEntryType.token, title: 't'),
      ],
    );

    await backend.save(document);

    expect(store.values.keys, [KeychainVaultBackend.storageKey]);
    expect(await backend.load(), document);
  });

  test('clear removes the stored document', () async {
    final store = _FakeStore();
    final backend = KeychainVaultBackend(store);
    await backend.save(const VaultDocument());
    await backend.clear();
    expect(await backend.load(), isNull);
    expect(store.values, isEmpty);
  });
}
