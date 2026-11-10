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

  test(
    'keeps the legacy keychain copy when the saved row drops the vault link',
    () async {
      // The home-plane catalog stores `SshServerProfile`, which has no
      // `vaultEntryId`. Deleting the keychain copy would leave that row with
      // no reachable credential at all.
      final vault = await _vault();
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
        repository: _VaultReferenceDroppingRepository(),
        credentialStore: credentials,
      );

      expect(
        await vault.readField(result.capture.entryId, 'password'),
        'legacy',
      );
      expect(await credentials.loadPassword('p1'), 'legacy');
    },
  );

  test(
    'owner lookup recovers the entry for a credential-free projection',
    () async {
      final vault = await _vault();
      final capture = VaultCredentialCapture(vault: vault);
      final result = await capture.captureSsh(profile, password: 'secret');

      final found = await findVaultOwnerEntry(
        vault,
        ownerKind: vaultOwnerKindSshProfile,
        ownerId: profile.id,
      );

      expect(found?.id, result.entryId);
      expect(await vault.readField(found!.id, 'password'), 'secret');
    },
  );

  group('resolveSshVaultFieldReader', () {
    test('reads the field by linked entry id', () async {
      final vault = await _vault();
      final capture = VaultCredentialCapture(vault: vault);
      final result = await capture.captureSsh(profile, password: 'secret');
      final linked = profile.copyWith(vaultEntryId: result.entryId);

      expect(await resolveSshVaultFieldReader(vault, linked)('password'), 'secret');
    });

    test('falls back to the owner pair when the row has no vault link', () async {
      final vault = await _vault();
      await VaultCredentialCapture(vault: vault).captureSsh(
        profile,
        password: 'secret',
      );

      expect(await resolveSshVaultFieldReader(vault, profile)('password'), 'secret');
    });

    test('returns null with no entry and for an absent field', () async {
      final vault = await _vault();
      await VaultCredentialCapture(vault: vault).captureSsh(
        profile,
        password: 'secret',
      );
      final reader = resolveSshVaultFieldReader(vault, profile);

      expect(await reader('passphrase'), isNull);
      expect(await resolveSshVaultFieldReader(await _vault(), profile)('password'), isNull);
    });
  });

  group('editor test credentials', () {
    late InMemorySshCredentialStore credentials;

    setUp(() => credentials = InMemorySshCredentialStore());

    test('typed password wins over the stored vault value', () async {
      final secrets = await resolveSshEditorTestSecrets(
        authType: SshAuthType.password,
        profileId: 'p1',
        passwordText: 'typed',
        privateKeyPem: '',
        passphraseText: '',
        vaultEntryId: 'v1',
        readVaultField: (_) async => 'stored',
        credentialStore: credentials,
      );

      expect(secrets.password, 'typed');
      expect(secrets.privateKey, isNull);
      expect(secrets.passphrase, isNull);
    });

    test('empty password falls back to the vault, then the keychain', () async {
      await credentials.savePassword('p1', 'legacy');
      Future<SshEditorSecretInputs> resolve({
        required String? vaultEntryId,
        required String? stored,
      }) {
        return resolveSshEditorTestSecrets(
          authType: SshAuthType.password,
          profileId: 'p1',
          passwordText: '',
          privateKeyPem: '',
          passphraseText: '',
          vaultEntryId: vaultEntryId,
          readVaultField: stored == null ? null : (_) async => stored,
          credentialStore: credentials,
        );
      }

      expect(
        (await resolve(vaultEntryId: 'v1', stored: 'stored')).password,
        'stored',
      );
      expect(
        (await resolve(vaultEntryId: null, stored: null)).password,
        'legacy',
      );
    });

    test('private key falls back to the vault, then the keychain', () async {
      await credentials.savePrivateKey('p1', 'legacy-pem');
      await credentials.savePrivateKeyPassphrase('p1', 'legacy-pass');
      Future<SshEditorSecretInputs> resolve({
        required String? vaultEntryId,
        required String? storedKey,
      }) {
        return resolveSshEditorTestSecrets(
          authType: SshAuthType.privateKey,
          profileId: 'p1',
          passwordText: 'ignored',
          privateKeyPem: '',
          passphraseText: '',
          vaultEntryId: vaultEntryId,
          readVaultField: storedKey == null
              ? null
              : (field) async => switch (field) {
                  'privateKey' => storedKey,
                  'passphrase' => 'vault-pass',
                  _ => null,
                },
          credentialStore: credentials,
        );
      }

      final fromVault = await resolve(
        vaultEntryId: 'v1',
        storedKey: 'vault-pem',
      );
      expect(fromVault.privateKey, 'vault-pem');
      expect(fromVault.passphrase, 'vault-pass');
      expect(fromVault.password, isNull);

      final fromKeychain = await resolve(vaultEntryId: null, storedKey: null);
      expect(fromKeychain.privateKey, 'legacy-pem');
      expect(fromKeychain.passphrase, 'legacy-pass');
    });
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

  test('editor mapping keeps linked empties and clears the inactive auth', () {
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.password,
        linked: true,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ),
      (password: null, privateKey: '', passphrase: ''),
    );
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.privateKey,
        linked: true,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ),
      (password: '', privateKey: null, passphrase: null),
    );
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.password,
        linked: false,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ).password,
      '',
      reason: 'unlinked empty lets the writer adopt the keychain value',
    );
  });
}

class _ThrowingSshProfileRepository implements SshProfileRepository {
  @override
  Future<void> save(SshProfile profile) async =>
      throw StateError('save failed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mimics the home-plane server catalog: the row it keeps has no
/// `vaultEntryId`.
class _VaultReferenceDroppingRepository extends SshProfileRepository {
  _VaultReferenceDroppingRepository() : super(storage: fakeHomeStorage());

  SshProfile? _stored;

  @override
  Future<void> save(SshProfile profile) async {
    _stored = SshProfile(
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      authType: profile.authType,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
    );
  }

  @override
  Future<SshProfile?> findById(String profileId) async =>
      _stored?.id == profileId ? _stored : null;
}

class _LockedVaultService implements VaultService {
  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
