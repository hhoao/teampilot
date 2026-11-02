import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/services/provider_usage/managed_provider_secret_store.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/legacy_import.dart';
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

class _Harness {
  _Harness(this.fs, this.storage, this.vault, this.capture);

  final InMemoryFilesystem fs;
  final HomeStorage storage;
  final VaultService vault;
  final VaultCredentialCapture capture;
}

Future<_Harness> _harness() async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final storage = fakeHomeStorage(filesystem: fs);
  final vault = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(
        rootDir: '/root/vault',
        fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
      ),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await vault.initialize();
  return _Harness(fs, storage, vault, VaultCredentialCapture(vault: vault));
}

VaultLegacyImportService _importer(
  _Harness h, {
  VaultService? vault,
  VaultCredentialCapture? capture,
  SshProfileRepository? sshProfiles,
  SshCredentialStore? sshCredentials,
  AppProviderRepository? appProviders,
  ManagedProviderRepository? managedProviders,
  ManagedProviderSecretStore? managedSecrets,
  GithubCredentialsStore? github,
}) => VaultLegacyImportService(
  vault: vault ?? h.vault,
  capture: capture ?? h.capture,
  sshProfiles: sshProfiles ?? SshProfileRepository(storage: h.storage),
  sshCredentials: sshCredentials ?? InMemorySshCredentialStore(),
  appProviders:
      appProviders ?? AppProviderRepository(storage: h.storage, fs: h.fs),
  managedProviders:
      managedProviders ??
      ManagedProviderRepository(
        storage: h.storage,
        fs: h.fs,
        configPath: '/tp/managed.json',
        onProvidersDeleted: (_) async {},
      ),
  managedSecrets: managedSecrets ?? ManagedProviderSecretStore(_FakeStore()),
  github: github ?? GithubCredentialsStore(kv: _FakeStore()),
);

void main() {
  test('imports every legacy secret once', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'p1', name: 'Server', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('p1', 'pw');

    final appProviders = AppProviderRepository(storage: h.storage, fs: h.fs);
    await appProviders.saveProviders(CliTool.claude, const [
      AppProviderConfig(
        id: 'openai',
        cli: CliTool.claude,
        name: 'OpenAI',
        apiKey: 'sk',
      ),
    ]);

    final managedRepo = ManagedProviderRepository(
      storage: h.storage,
      fs: h.fs,
      configPath: '/tp/managed.json',
      onProvidersDeleted: (_) async {},
    );
    final managedSecrets = ManagedProviderSecretStore(_FakeStore());
    await managedRepo.save([
      ManagedProvider(
        id: 'm1',
        name: 'Usage',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'http_json_mapping',
        credentialRef: 'managed-provider:m1',
      ),
    ]);
    await managedSecrets.write('managed-provider:m1', {'apiKey': 'usage-key'});

    final githubKv = _FakeStore();
    await githubKv.write('teampilot.github.v1.token', 'ghp');
    await githubKv.write('teampilot.github.v1.login', 'me');
    await githubKv.write('teampilot.github.v1.source', 'oauth');
    final github = GithubCredentialsStore(
      kv: githubKv,
      vault: h.vault,
      vaultCapture: h.capture,
      ensureVaultUnlocked: () async => true,
    );

    final importer = _importer(
      h,
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
      appProviders: appProviders,
      managedProviders: managedRepo,
      managedSecrets: managedSecrets,
      github: github,
    );
    await importer.runOnce();

    expect((await sshProfiles.loadAll()).single.vaultEntryId, isNotNull);
    expect(await sshCredentials.loadPassword('p1'), isNull);
    final provider = (await appProviders.loadProviders(CliTool.claude)).single;
    expect(provider.credentialLink, startsWith('vault:'));
    expect(provider.apiKey, isEmpty);
    final managed = (await managedRepo.load()).single;
    expect(managed.vaultEntryId, isNotNull);
    expect(await managedSecrets.read('managed-provider:m1'), isNotNull);
    expect(
      (await h.vault.list()).any(
        (entry) => entry.extra['ownerKind'] == vaultOwnerKindGithub,
      ),
      isTrue,
    );
    expect(
      await githubKv.read('teampilot.github.v1.token'),
      isNull,
      reason: 'the legacy GitHub token is deleted after the pointer is stored',
    );
    expect(h.vault.legacyImportVersion, 1);

    final before = (await h.vault.list()).length;
    await importer.runOnce();
    expect((await h.vault.list()).length, before, reason: 'idempotent');
  });

  test('a failed owner keeps its legacy data and blocks the marker', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'bad', name: 'Bad', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('bad', 'pw');
    final importer = _importer(
      h,
      capture: _FailingSshCapture(h.vault),
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
    );

    await importer.runOnce();
    expect((await sshProfiles.loadAll()).single.vaultEntryId, isNull);
    expect(await sshCredentials.loadPassword('bad'), 'pw');
    expect(h.vault.legacyImportVersion, 0);
  });

  test('one failed SSH profile does not stop the others', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.saveAll(const [
      SshProfile(id: 'bad', name: 'Bad', host: 'h', username: 'u'),
      SshProfile(id: 'good', name: 'Good', host: 'h', username: 'u'),
    ]);
    await sshCredentials.savePassword('bad', 'pw-bad');
    await sshCredentials.savePassword('good', 'pw-good');
    final importer = _importer(
      h,
      capture: _FailingSshCapture(h.vault),
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
    );

    await importer.runOnce();
    final profiles = {for (final p in await sshProfiles.loadAll()) p.id: p};
    expect(profiles['bad']!.vaultEntryId, isNull);
    expect(await sshCredentials.loadPassword('bad'), 'pw-bad');
    expect(profiles['good']!.vaultEntryId, isNotNull);
    expect(await sshCredentials.loadPassword('good'), isNull);
    expect(h.vault.legacyImportVersion, 0);
  });

  test(
    'a failed provider capture keeps its key and blocks the marker',
    () async {
      final h = await _harness();
      final appProviders = AppProviderRepository(storage: h.storage, fs: h.fs);
      await appProviders.saveProviders(CliTool.claude, const [
        AppProviderConfig(
          id: 'openai',
          cli: CliTool.claude,
          name: 'OpenAI',
          apiKey: 'sk',
        ),
      ]);
      final importer = _importer(
        h,
        capture: _FailingProviderCapture(h.vault),
        appProviders: appProviders,
      );

      await importer.runOnce();
      final provider = (await appProviders.loadProviders(
        CliTool.claude,
      )).single;
      expect(provider.credentialLink, isEmpty);
      expect(provider.apiKey, 'sk');
      expect(h.vault.legacyImportVersion, 0);
    },
  );

  test('a failed provider save leaves no vault link in the cache', () async {
    final h = await _harness();
    await AppProviderRepository(storage: h.storage, fs: h.fs).saveProviders(
      CliTool.claude,
      const [
        AppProviderConfig(
          id: 'openai',
          cli: CliTool.claude,
          name: 'OpenAI',
          apiKey: 'sk',
        ),
      ],
    );
    final appProviders = _FailingSaveAppProviders(storage: h.storage, fs: h.fs);
    final importer = _importer(h, appProviders: appProviders);

    await importer.runOnce();
    final provider = (await appProviders.loadProviders(CliTool.claude)).single;
    expect(provider.credentialLink, isEmpty);
    expect(provider.apiKey, 'sk');
    expect(h.vault.legacyImportVersion, 0);
  });

  test('a dangling GitHub pointer is repaired from the legacy token', () async {
    final h = await _harness();
    final githubKv = _FakeStore();
    await githubKv.write('teampilot.github.v1.token', 'ghp');
    await githubKv.write('teampilot.github.v1.source', 'pat');
    await githubKv.write('teampilot.github.v1.vault_entry', 'gone');
    final github = GithubCredentialsStore(
      kv: githubKv,
      vault: h.vault,
      vaultCapture: h.capture,
      ensureVaultUnlocked: () async => true,
    );

    await _importer(h, github: github).runOnce();

    final pointer = await github.storedVaultEntryId();
    expect(pointer, isNotNull);
    expect(pointer, isNot('gone'));
    expect(await h.vault.readField(pointer!, 'token'), 'ghp');
    expect(
      await githubKv.read('teampilot.github.v1.token'),
      isNull,
      reason: 'the repaired pointer makes the legacy token redundant',
    );
    expect(h.vault.legacyImportVersion, 1);
  });

  test('locked vault is a no-op', () async {
    final h = await _harness();
    final sshProfiles = SshProfileRepository(storage: h.storage);
    final sshCredentials = InMemorySshCredentialStore();
    await sshProfiles.save(
      const SshProfile(id: 'p1', name: 'Server', host: 'h', username: 'u'),
    );
    await sshCredentials.savePassword('p1', 'pw');
    final importer = _importer(
      h,
      vault: _LockedVault(h.vault),
      sshProfiles: sshProfiles,
      sshCredentials: sshCredentials,
    );

    await importer.runOnce();
    expect(await sshCredentials.loadPassword('p1'), 'pw');
    expect((await h.vault.list()), isEmpty);
    expect(h.vault.legacyImportVersion, 0);
  });
}

class _FailingSshCapture extends VaultCredentialCapture {
  _FailingSshCapture(VaultService vault) : super(vault: vault);

  @override
  Future<VaultCaptureResult> captureSsh(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
    String? relayGrant,
  }) async {
    if (profile.id == 'bad') {
      throw const VaultCaptureException('injected');
    }
    return super.captureSsh(
      profile,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      relayGrant: relayGrant,
    );
  }
}

class _FailingSaveAppProviders extends AppProviderRepository {
  _FailingSaveAppProviders({required super.storage, super.fs});

  @override
  Future<void> saveProviders(
    CliTool cli,
    List<AppProviderConfig> providers,
  ) async {
    throw StateError('injected');
  }
}

class _FailingProviderCapture extends VaultCredentialCapture {
  _FailingProviderCapture(VaultService vault) : super(vault: vault);

  @override
  Future<VaultCaptureResult> captureProvider(
    AppProviderConfig provider, {
    String? apiKey,
  }) async {
    if (provider.id == 'openai') {
      throw const VaultCaptureException('injected');
    }
    return super.captureProvider(provider, apiKey: apiKey);
  }
}

class _LockedVault implements VaultService {
  _LockedVault(this._delegate);
  final VaultService _delegate;
  @override
  bool get isEncrypted => _delegate.isEncrypted;
  @override
  bool get isUnlocked => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
