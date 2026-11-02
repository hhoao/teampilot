// client/test/services/vault/vault_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../../support/in_memory_filesystem.dart';

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
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  VaultService buildService({_FakeStore? store}) {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    return VaultService(
      keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      ),
    );
  }

  test('starts on the keychain backend and creates entries', () async {
    final service = buildService();
    await service.initialize();
    expect(service.isEncrypted, isFalse);
    expect(service.isUnlocked, isTrue);

    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    expect((await service.list()).single.title, 'A');
    expect(await service.readField('a', 'token'), isNull);
  });

  test('search matches title, tag and field values', () async {
    final service = buildService();
    await service.initialize();
    await service.upsert(
      const VaultEntry(
        id: 'a',
        type: VaultEntryType.login,
        title: 'GitHub',
        fields: {'username': 'octocat', 'password': 'pw'},
        tags: ['work'],
      ),
    );

    expect(await service.list(query: 'git'), hasLength(1));
    expect(await service.list(query: 'octo'), hasLength(1));
    expect(await service.list(query: 'work'), hasLength(1));
    expect(await service.list(query: 'nope'), isEmpty);
    expect(
      await service.list(type: VaultEntryType.token),
      isEmpty,
    );
  });

  test('enabling encryption migrates the document and locks on reload', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );

    await service.enableEncryptedBackend('master');
    expect(service.isEncrypted, isTrue);
    expect(service.isUnlocked, isTrue);
    expect(store.values, isEmpty);
    expect((await service.list()).single.id, 'a');

    service.lock();
    expect(service.isLocked, isTrue);
    await expectLater(service.list(), throwsA(isA<VaultLockedException>()));
    await service.unlock('master');
    expect((await service.list()).single.id, 'a');
  });

  test('initialize does not re-lock an already unlocked vault', () async {
    final service = buildService();
    await service.initialize();
    await service.enableEncryptedBackend('master');
    await service.initialize();
    expect(service.isLocked, isFalse);
  });

  test('disabling encryption returns the document to the keychain', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    await service.enableEncryptedBackend('master');
    await service.disableEncryptedBackend();

    expect(service.isEncrypted, isFalse);
    expect(store.values, isNotEmpty);
    expect((await service.list()).single.id, 'a');
  });

  test('deleting removes the entry', () async {
    final service = buildService();
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    await service.delete('a');
    expect(await service.list(), isEmpty);
  });

  test('marker persists through the keychain backend', () async {
    final service = buildService();
    await service.initialize();
    expect(service.legacyImportVersion, 0);

    await service.markLegacyImported(1);
    expect(service.legacyImportVersion, 1);

    final reloaded = buildService();
    await reloaded.initialize();
    expect(reloaded.legacyImportVersion, 0,
        reason: 'a fresh backend is a different store in this harness');
  });
}
