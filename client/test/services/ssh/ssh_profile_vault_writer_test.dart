import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/ssh/ssh_profile_vault_writer.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';

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

Future<VaultService> _vault({_FakeStore? store}) async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
  );

  test(
    'stores a password in the vault, links the profile and clears nothing',
    () async {
      final store = _FakeStore();
      final vault = await _vault(store: store);
      final repository = SshProfileRepository(storage: fakeHomeStorage());
      final credentials = InMemorySshCredentialStore();
      final capture = VaultCredentialCapture(vault: vault);
      final gate = VaultUnlockGate(vault: vault, prompt: () async => true);

      final result = await saveSshProfileWithVault(
        profile: profile,
        password: 'secret',
        privateKey: null,
        passphrase: null,
        capture: capture,
        unlockGate: gate,
        repository: repository,
        credentialStore: credentials,
      );

      expect(result.profile.vaultEntryId, result.capture.entryId);
      expect(
        (await repository.loadAll()).single.vaultEntryId,
        result.capture.entryId,
      );
      expect(
        await vault.readField(result.capture.entryId, 'password'),
        'secret',
      );
      expect(await credentials.loadPassword('p1'), isNull);
    },
  );

  test('keeps the paired-relay grant inside the same entry', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'grant-1');
    final capture = VaultCredentialCapture(vault: vault);

    final result = await saveSshProfileWithVault(
      profile: profile,
      password: 'secret',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      repository: repository,
      credentialStore: credentials,
    );

    expect(
      await vault.readField(result.capture.entryId, 'relayGrant'),
      'grant-1',
    );
  });

  test('repository failure rolls the capture back', () async {
    final vault = await _vault();
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);

    await expectLater(
      saveSshProfileWithVault(
        profile: profile,
        password: 'secret',
        privateKey: null,
        passphrase: null,
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        repository: _ThrowingSshProfileRepository(),
        credentialStore: credentials,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });

  test('adopts legacy keychain secrets and deletes them after save', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    await credentials.savePassword('p1', 'legacy');
    final capture = VaultCredentialCapture(vault: vault);

    final result = await saveSshProfileWithVault(
      profile: profile,
      password: '',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      repository: repository,
      credentialStore: credentials,
    );

    expect(await vault.readField(result.capture.entryId, 'password'), 'legacy');
    expect(await credentials.loadPassword('p1'), isNull);
  });

  test('blocked vault aborts without saving the profile or an entry', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);
    final blocked = VaultUnlockGate(
      vault: _LockedVaultService(),
      prompt: () async => false,
    );

    await expectLater(
      saveSshProfileWithVault(
        profile: profile,
        password: 'secret',
        privateKey: null,
        passphrase: null,
        capture: capture,
        unlockGate: blocked,
        repository: repository,
        credentialStore: credentials,
      ),
      throwsA(isA<VaultSaveBlockedException>()),
    );
    expect(await repository.loadAll(), isEmpty);
    expect(await vault.list(), isEmpty);
  });
}

class _ThrowingSshProfileRepository implements SshProfileRepository {
  @override
  Future<void> save(SshProfile profile) async =>
      throw StateError('save failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LockedVaultService implements VaultService {
  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
