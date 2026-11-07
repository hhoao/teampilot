import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/home_vault_service.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_split_migration.dart';

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

const _sshPassword = VaultEntry(
  id: 'ssh-1',
  type: VaultEntryType.sshPassword,
  title: 'dev box',
  fields: {'password': 'secret'},
);

const _sshKey = VaultEntry(
  id: 'ssh-2',
  type: VaultEntryType.sshPrivateKey,
  title: 'prod box',
  fields: {'privateKey': 'PEM'},
);

const _githubToken = VaultEntry(
  id: 'biz-1',
  type: VaultEntryType.token,
  title: 'GitHub',
  fields: {'token': 'ghp_xxx'},
  extra: {'ownerKind': 'github', 'ownerId': 'me'},
);

const _providerKey = VaultEntry(
  id: 'biz-2',
  type: VaultEntryType.apiKey,
  title: 'Provider key',
  fields: {'apiKey': 'sk-xxx'},
  extra: {'ownerKind': 'appProvider', 'ownerId': 'p1'},
);

void main() {
  VaultService buildVault({
    required _FakeStore store,
    required InMemoryFilesystem fs,
    VaultService? Function()? homeVault,
    String rootDir = '/root/vault',
  }) {
    return VaultService(
      keychainBackend: KeychainVaultBackend(store),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: rootDir, fs: fs),
      ),
      homeVault: homeVault,
    );
  }

  group('home-plane vault split', () {
    test('SSH credentials stay on the device, business go to home', () async {
      final deviceFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final homeFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final store = _FakeStore();
      final home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: homeFs),
        keyStore: store,
      );
      final device = buildVault(
        store: store,
        fs: deviceFs,
        homeVault: () => home,
      );
      await device.initialize();

      await device.upsert(_sshPassword);
      await device.upsert(_sshKey);
      await device.upsert(_githubToken);
      await device.upsert(_providerKey);

      // The device vault never receives business credentials.
      final deviceDocument = await KeychainVaultBackend(store).load();
      expect(deviceDocument!.entries.map((e) => e.id), [
        'ssh-1',
        'ssh-2',
      ]);
      // The home-plane file holds only business credentials.
      final homeRaw = homeFs.files['/tp/vault/business.json'];
      expect(homeRaw, isNotNull);
      expect(homeRaw, contains('biz-1'));
      expect(homeRaw, contains('biz-2'));
      expect(homeRaw, isNot(contains('ssh-1')));
    });

    test('list merges both planes and readField resolves either', () async {
      final deviceFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final homeFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final store = _FakeStore();
      final home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: homeFs),
        keyStore: store,
      );
      final device = buildVault(
        store: store,
        fs: deviceFs,
        homeVault: () => home,
      );
      await device.initialize();

      await device.upsert(_sshPassword);
      await device.upsert(_githubToken);

      final ids = (await device.list()).map((e) => e.id).toSet();
      expect(ids, {'ssh-1', 'biz-1'});
      expect(await device.readField('ssh-1', 'password'), 'secret');
      expect(await device.readField('biz-1', 'token'), 'ghp_xxx');
      expect(await device.get('biz-1'), isNotNull);
    });

    test('a broken home plane never breaks the device vault', () async {
      final deviceFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final failingFs = _ThrowingFilesystem();
      final store = _FakeStore();
      final home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: failingFs),
        keyStore: store,
      );
      final device = buildVault(
        store: store,
        fs: deviceFs,
        homeVault: () => home,
      );
      await device.initialize();

      await device.upsert(_sshPassword);
      expect(await device.readField('ssh-1', 'password'), 'secret');

      // Business writes fall back to the device instead of being lost.
      await device.upsert(_githubToken);
      expect(await device.readField('biz-1', 'token'), 'ghp_xxx');
    });

    test('a home-plane swap routes business writes to the new host', () async {
      final deviceFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final hostA = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final hostB = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final store = _FakeStore();
      var home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: hostA),
        keyStore: store,
      );
      final device = buildVault(
        store: store,
        fs: deviceFs,
        homeVault: () => home,
      );
      await device.initialize();

      await device.upsert(_providerKey);
      expect(hostA.files['/tp/vault/business.json'], contains('biz-2'));

      // Simulate switching the home plane: a fresh service backed by hostB.
      home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: hostB),
        keyStore: store,
      );
      await home.initialize();
      await device.upsert(_githubToken);

      expect(hostB.files['/tp/vault/business.json'], contains('biz-1'));
      expect(hostB.files['/tp/vault/business.json'], isNot(contains('biz-2')));
    });
  });

  group('one-shot migration', () {
    test('copies business entries without deleting SSH credentials', () async {
      final deviceFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final homeFs = InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      );
      final store = _FakeStore();
      // Legacy device vault holds both kinds (pre-split state).
      final legacy = buildVault(store: store, fs: deviceFs);
      await legacy.initialize();
      await legacy.upsert(_sshPassword);
      await legacy.upsert(_githubToken);
      await legacy.upsert(_providerKey);

      final home = HomeVaultService(
        storage: fakeHomeStorage(filesystem: homeFs),
        keyStore: store,
      );
      final copied = await migrateBusinessVaultEntries(
        device: legacy,
        home: home,
      );
      expect(copied, 2);

      // Zero loss: SSH credentials remain on the device.
      final deviceDocument = await KeychainVaultBackend(store).load();
      expect(deviceDocument!.entries.map((e) => e.id), containsAll([
        'ssh-1',
        'biz-1',
        'biz-2',
      ]));
      final homeRaw = homeFs.files['/tp/vault/business.json'];
      expect(homeRaw, contains('biz-1'));
      expect(homeRaw, contains('biz-2'));
      expect(homeRaw, isNot(contains('ssh-1')));

      // Idempotent: a second pass copies nothing.
      expect(
        await migrateBusinessVaultEntries(device: legacy, home: home),
        0,
      );
    });
  });
}

class _ThrowingFilesystem extends InMemoryFilesystem {
  @override
  Future<void> writeString(String path, String content) async =>
      throw StateError('SSH transport closed');

  @override
  Future<void> atomicWrite(String path, String content) async =>
      throw StateError('SSH transport closed');
}
