import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
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
  test('migration copies the password and only then clears the keychain', () async {
    final sshStore = InMemorySshCredentialStore();
    final profileRepo = SshProfileRepository(storage: fakeHomeStorage());
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final vault = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    await vault.initialize();

    const profile = SshProfile(
      id: 'p1',
      name: 'Server',
      host: 'example.com',
      username: 'u',
    );
    await profileRepo.save(profile);
    await sshStore.savePassword('p1', 'secret');

    final cubit = SshProfileCubit(
      profileRepository: profileRepo,
      credentialStore: sshStore,
      vaultService: vault,
    );
    addTearDown(cubit.close);
    await cubit.load();

    final entryId = await cubit.migrateToVault('p1');
    expect(entryId, isNotNull);
    expect(await vault.readField(entryId!, 'password'), 'secret');

    final migrated = (await profileRepo.loadAll()).single;
    expect(migrated.vaultEntryId, entryId);
    expect(await sshStore.loadPassword('p1'), isNull);
  });
}
