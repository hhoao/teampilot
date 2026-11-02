import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';

import '../../support/in_memory_filesystem.dart';

class ThrowingSecureKeyValueStore implements SecureKeyValueStore {
  ThrowingSecureKeyValueStore(this.inner, {required this.shouldThrowOnWrite});

  final SecureKeyValueStore inner;
  final bool Function(String key) shouldThrowOnWrite;

  @override
  Future<void> delete(String key) => inner.delete(key);

  @override
  Future<String?> read(String key) => inner.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (shouldThrowOnWrite(key)) {
      throw StateError('write failed for $key');
    }
    await inner.write(key, value);
  }
}

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
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

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<VaultService> _githubVault() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeStore()),
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

class _LockedGithubVault implements VaultService {
  _LockedGithubVault(this._delegate);
  final VaultService _delegate;
  @override
  bool get isEncrypted => _delegate.isEncrypted;
  @override
  bool get isUnlocked => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('saveOAuth round-trips token, login, and source', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.saveOAuth(token: 'gho_test', login: 'alice');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'gho_test');
    expect(snapshot?.login, 'alice');
    expect(snapshot?.source, GithubCredentialSource.oauth);
  });

  test('savePat round-trips token and source', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test', login: 'bob');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_test');
    expect(snapshot?.login, 'bob');
    expect(snapshot?.source, GithubCredentialSource.pat);
  });

  test('savePat without login stores token only', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_test');
    expect(snapshot?.login, isNull);
    expect(snapshot?.source, GithubCredentialSource.pat);
  });

  test('clearStored removes stored credentials', () async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    await store.savePat('ghp_test', login: 'alice');
    await store.clearStored();

    expect(await store.readStored(), isNull);
  });

  test('resolveToken prefers stored token over env fallback', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    await store.savePat('ghp_saved');

    expect(await store.resolveToken(), 'ghp_saved');
  });

  test('resolveToken falls back to env when store is empty', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );

    expect(await store.resolveToken(), 'ghp_env');
  });

  test('clearStored leaves env resolvable', () async {
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      readEnvToken: () => 'ghp_env',
    );
    await store.savePat('ghp_saved');
    await store.clearStored();

    expect(await store.resolveToken(), 'ghp_env');
  });

  test('legacy hub publish token migrates once into pat storage', () async {
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    final store = GithubCredentialsStore(kv: kv);

    expect(await store.resolveToken(), 'ghp_legacy');

    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_legacy');
    expect(snapshot?.source, GithubCredentialSource.pat);
    expect(
      kv.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isFalse,
    );

    // Second read does not re-migrate or fail.
    expect(await store.resolveToken(), 'ghp_legacy');
  });

  test('legacy migration retries after storage write failure', () async {
    final inner = InMemorySecureKeyValueStore();
    inner.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    var failWrites = true;
    final kv = ThrowingSecureKeyValueStore(
      inner,
      shouldThrowOnWrite: (_) => failWrites,
    );
    final store = GithubCredentialsStore(kv: kv);

    await expectLater(
      store.migrateLegacyHubPublishTokenIfNeeded(),
      throwsA(isA<StateError>()),
    );
    expect(
      inner.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isTrue,
    );
    expect(inner.values.containsKey('teampilot.github.v1.token'), isFalse);

    failWrites = false;
    await store.migrateLegacyHubPublishTokenIfNeeded();

    expect(await store.resolveToken(), 'ghp_legacy');
    expect(
      inner.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isFalse,
    );
  });

  test('migrateLegacyHubPublishTokenIfNeeded is idempotent', () async {
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_legacy';
    final store = GithubCredentialsStore(kv: kv);

    await store.migrateLegacyHubPublishTokenIfNeeded();
    await store.migrateLegacyHubPublishTokenIfNeeded();

    expect(await store.readStored(), isNotNull);
    expect(
      kv.values.containsKey('teampilot.hub_publish.v1.github_token'),
      isFalse,
    );
  });

  test('stores OAuth credentials in the vault and reads the pointer', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    final store = GithubCredentialsStore(
      kv: kv,
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );

    await store.saveOAuth(token: 'ghp_x', login: 'me');
    final snapshot = await store.readStored();
    expect(snapshot?.token, 'ghp_x');
    expect(snapshot?.login, 'me');
    expect(snapshot?.source, GithubCredentialSource.oauth);
    expect(await vault.list(), hasLength(1));
    expect(kv.values['teampilot.github.v1.vault_entry'], isNotEmpty);
    expect(kv.values.containsKey('teampilot.github.v1.token'), isFalse);
    expect(kv.values.containsKey('teampilot.github.v1.login'), isFalse);
    expect(kv.values.containsKey('teampilot.github.v1.source'), isFalse);

    await store.clearStored();
    expect(await store.readStored(), isNull);
    expect(await vault.list(), isEmpty);
  });

  test('a dangling pointer falls back to the legacy keys', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.github.v1.vault_entry'] = 'missing-entry';
    kv.values['teampilot.github.v1.token'] = 'ghp_legacy';
    kv.values['teampilot.github.v1.login'] = 'alice';
    kv.values['teampilot.github.v1.source'] = 'pat';
    final store = GithubCredentialsStore(kv: kv, vault: vault);

    final snapshot = await store.readStored();

    expect(snapshot?.token, 'ghp_legacy');
    expect(snapshot?.login, 'alice');
    expect(snapshot?.source, GithubCredentialSource.pat);
  });

  test('a vault read failure falls back to the legacy keys', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.github.v1.vault_entry'] = 'entry-1';
    kv.values['teampilot.github.v1.token'] = 'ghp_legacy';
    final store = GithubCredentialsStore(
      kv: kv,
      vault: _LockedGithubVault(vault),
      vaultCapture: VaultCredentialCapture(vault: _LockedGithubVault(vault)),
      ensureVaultUnlocked: () async => false,
    );

    final snapshot = await store.readStored();

    expect(snapshot?.token, 'ghp_legacy');
  });

  test('rolls back the capture when the pointer write fails', () async {
    final vault = await _githubVault();
    final inner = InMemorySecureKeyValueStore();
    final kv = ThrowingSecureKeyValueStore(
      inner,
      shouldThrowOnWrite: (key) => key == 'teampilot.github.v1.vault_entry',
    );
    final store = GithubCredentialsStore(
      kv: kv,
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );

    await expectLater(
      store.savePat('ghp_rollback'),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });

  test('a dangling pointer keeps the legacy hub token resolvable', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.github.v1.vault_entry'] = 'missing-entry';
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_hub';
    final store = GithubCredentialsStore(kv: kv, vault: vault);

    final snapshot = await store.readStored();

    expect(snapshot?.token, 'ghp_hub');
    expect(snapshot?.source, GithubCredentialSource.pat);
    // The credential survives the pointer miss: the unchanged migration turns
    // the hub token into the regular legacy token instead of dropping it.
    expect(kv.values['teampilot.github.v1.token'], 'ghp_hub');
    expect(await store.resolveToken(), 'ghp_hub');
  });

  test('a locked vault keeps the legacy hub token', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.github.v1.vault_entry'] = 'entry-1';
    kv.values['teampilot.hub_publish.v1.github_token'] = 'ghp_hub';
    final store = GithubCredentialsStore(
      kv: kv,
      vault: _LockedGithubVault(vault),
    );

    expect(await store.readStored(), isNull);
    expect(
      kv.values['teampilot.hub_publish.v1.github_token'],
      'ghp_hub',
    );
  });

  test('a refused unlock aborts the save', () async {
    final vault = await _githubVault();
    final store = GithubCredentialsStore(
      kv: InMemorySecureKeyValueStore(),
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: _LockedGithubVault(vault)),
      ensureVaultUnlocked: () async => false,
    );
    await expectLater(
      store.savePat('ghp_y'),
      throwsA(isA<VaultSaveBlockedException>()),
    );
  });

  test('a refused unlock leaves the legacy keys untouched', () async {
    final vault = await _githubVault();
    final kv = InMemorySecureKeyValueStore();
    kv.values['teampilot.github.v1.token'] = 'ghp_legacy';
    kv.values['teampilot.github.v1.login'] = 'alice';
    kv.values['teampilot.github.v1.source'] = 'pat';
    final store = GithubCredentialsStore(
      kv: kv,
      vault: vault,
      vaultCapture: VaultCredentialCapture(vault: _LockedGithubVault(vault)),
      ensureVaultUnlocked: () async => false,
    );

    await expectLater(
      store.savePat('ghp_new'),
      throwsA(isA<VaultSaveBlockedException>()),
    );

    expect(kv.values['teampilot.github.v1.token'], 'ghp_legacy');
    expect(kv.values['teampilot.github.v1.login'], 'alice');
    expect(kv.values['teampilot.github.v1.source'], 'pat');
    expect(await vault.list(), isEmpty);
  });
}
