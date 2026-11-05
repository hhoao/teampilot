import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/models/vault_reference.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_reference_indexer.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../support/in_memory_filesystem.dart';

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

  late VaultCubit cubit;
  late SshProfileRepository sshRepo;

  VaultService buildService() {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    return VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      ),
    );
  }

  setUp(() {
    final service = buildService();
    sshRepo = SshProfileRepository(storage: fakeHomeStorage());
    cubit = VaultCubit(
      service: service,
      sshProfiles: sshRepo,
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
  });

  tearDown(() => cubit.close());

  test('load exposes an unlocked keychain vault', () async {
    await cubit.load();
    expect(cubit.state.status, VaultStatus.ready);
    expect(cubit.state.entries, isEmpty);
  });

  test('save then search filters entries', () async {
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.login, title: 'GitHub'),
    );
    await cubit.save(
      const VaultEntry(id: 'b', type: VaultEntryType.token, title: 'Stripe'),
    );
    expect(cubit.state.entries, hasLength(2));

    await cubit.setQuery('git');
    expect(cubit.state.entries.single.id, 'a');
  });

  test('referencesFor finds SSH profiles pointing at an entry', () async {
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.sshPassword, title: 'A'),
    );
    await sshRepo.save(
      const SshProfile(
        id: 'p1',
        name: 'Server',
        host: 'example.com',
        username: 'u',
        vaultEntryId: 'a',
      ),
    );

    final refs = await cubit.referencesFor('a');
    expect(refs, hasLength(1));
    expect(refs.single.kind, VaultReferenceKind.sshProfile);
    expect(refs.single.label, 'Server');
  });

  test('an attached reference indexer replaces the fallback', () async {
    await cubit.load();
    cubit.attachReferenceIndexer(
      VaultReferenceIndexer([
        (id) async => const [
          VaultReference(
            kind: VaultReferenceKind.github,
            id: 'github',
            label: 'GitHub',
          ),
        ],
      ]),
    );

    final refs = await cubit.referencesFor('a');
    expect(refs.single.kind, VaultReferenceKind.github);
  });

  test('setQuery while locked surfaces error and keeps query', () async {
    await cubit.load();
    await cubit.enableEncryption('master');
    cubit.lock();
    await cubit.setQuery('x');
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.query, 'x');
  });

  test('enabling encryption twice surfaces error and clears busy', () async {
    await cubit.load();
    await cubit.enableEncryption('master');
    await cubit.enableEncryption('master');
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.busy, isFalse);
  });

  test('remove while locked surfaces error and clears busy', () async {
    await cubit.load();
    await cubit.enableEncryption('master');
    cubit.lock();
    await cubit.remove('nope');
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.busy, isFalse);
  });

  test('disabling encryption when not encrypted surfaces error and clears busy', () async {
    await cubit.load(); // keychain mode: disable is invalid
    await cubit.disableEncryption();
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.busy, isFalse);
  });

  test('onUnlocked fires after a successful unlock', () async {
    final service = buildService();
    await service.initialize();
    await service.enableEncryptedBackend('pass');
    service.lock();
    var calls = 0;
    final unlockedCubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
      onUnlocked: () async => calls++,
    );
    addTearDown(unlockedCubit.close);
    await unlockedCubit.unlock('pass');
    expect(calls, 1);
  });

  test('onUnlocked does not fire on load', () async {
    var calls = 0;
    final service = buildService();
    final loadCubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
      onUnlocked: () async => calls++,
    );
    addTearDown(loadCubit.close);
    await loadCubit.load();
    expect(calls, 0);
  });
}
