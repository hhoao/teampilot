import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
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

Future<VaultService> _service({_FakeStore? store}) async {
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: VaultRepository(rootDir: '/root/vault', fs: fs),
      crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
    ),
  );
  await service.initialize();
  return service;
}

void main() {
  const passwordProfile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
  );

  test('captures an SSH password entry and is idempotent', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);

    final first = await capture.captureSsh(passwordProfile, password: 'secret');
    expect(first.created, isTrue);
    final entry = (await service.get(first.entryId))!;
    expect(entry.title, 'Server');
    expect(entry.type, VaultEntryType.sshPassword);
    expect(entry.fields['password'], 'secret');
    expect(entry.extra['ownerKind'], vaultOwnerKindSshProfile);
    expect(entry.extra['ownerId'], 'p1');

    final renamed = passwordProfile.copyWith(name: 'Renamed');
    final second = await capture.captureSsh(renamed, password: 'secret2');
    expect(second.created, isFalse);
    expect(second.entryId, first.entryId);
    expect((await service.get(first.entryId))!.title, 'Renamed');
    expect((await service.get(first.entryId))!.fields['password'], 'secret2');
  });

  test('switching auth type removes the old secret field', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final id = (await capture.captureSsh(
      passwordProfile,
      password: 'pw',
    )).entryId;

    final keyProfile = passwordProfile.copyWith(
      authType: SshAuthType.privateKey,
    );
    await capture.captureSsh(
      keyProfile,
      password: '',
      privateKey: 'PEM',
      passphrase: 'pass',
    );
    final entry = (await service.get(id))!;
    expect(entry.type, VaultEntryType.sshPrivateKey);
    expect(entry.fields.containsKey('password'), isFalse);
    expect(entry.fields['privateKey'], 'PEM');
    expect(entry.fields['passphrase'], 'pass');
    expect(entry.revealAllowed, isFalse);
  });

  test('captures a provider entry with the vault apiKey', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    const provider = AppProviderConfig(
      id: 'openai',
      cli: CliTool.codex,
      name: 'OpenAI',
      apiKey: 'sk-1',
      baseUrl: 'https://api.example.com',
    );

    final result = await capture.captureProvider(
      provider,
      apiKey: provider.apiKey,
    );
    final entry = (await service.get(result.entryId))!;
    expect(entry.title, 'OpenAI');
    expect(entry.fields['apiKey'], 'sk-1');
    expect(entry.fields['baseUrl'], 'https://api.example.com');
    expect(entry.tags, contains('provider'));

    await capture.captureProvider(
      provider.copyWith(name: 'OpenAI 2', apiKey: 'sk-2'),
      apiKey: 'sk-2',
    );
    expect((await service.get(result.entryId))!.fields['apiKey'], 'sk-2');
    expect(await service.readField(result.entryId, 'apiKey'), 'sk-2');
  });

  test('capture preserves notes and provider key clear semantics', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    const provider = AppProviderConfig(
      id: 'p2',
      cli: CliTool.codex,
      name: 'Provider',
    );

    final created = await capture.captureProvider(provider, apiKey: 'k');
    final entry = (await service.get(created.entryId))!;
    await service.upsert(entry.copyWith(notes: 'hello'));

    await capture.captureProvider(provider);
    final kept = (await service.get(created.entryId))!;
    expect(kept.fields['apiKey'], 'k');
    expect(kept.notes, 'hello');

    await capture.captureProvider(provider, apiKey: '');
    expect(
      (await service.get(created.entryId))!.fields.containsKey('apiKey'),
      isFalse,
    );
  });

  test('managed capture merges fields', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final provider = ManagedProvider(
      id: 'm1',
      name: 'Usage',
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'http_json_mapping',
    );

    final first = await capture.captureManaged(provider, {'apiKey': 'a'});
    await capture.captureManaged(provider, {'secretKey': 'b'});
    final entry = (await service.get(first.entryId))!;
    expect(entry.fields, {'apiKey': 'a', 'secretKey': 'b'});
    expect(entry.type, VaultEntryType.custom);
    expect(entry.tags, contains('usage'));
  });

  test('github capture stores token, login and source', () async {
    final service = await _service();
    final capture = VaultCredentialCapture(vault: service);
    final result = await capture.captureGithub(
      token: 'ghp_x',
      login: 'me',
      source: 'oauth',
    );
    final entry = (await service.get(result.entryId))!;
    expect(entry.type, VaultEntryType.token);
    expect(entry.isSecretField('token'), isTrue);
    expect(entry.fields, {'token': 'ghp_x', 'login': 'me', 'source': 'oauth'});
    expect(entry.extra['ownerKind'], vaultOwnerKindGithub);
    expect(entry.extra['ownerId'], 'default');
  });

  test('verify failure restores the previous entry', () async {
    final store = _FakeStore();
    final service = await _service(store: store);
    final capture = VaultCredentialCapture(vault: service);
    await capture.captureSsh(passwordProfile, password: 'old');

    final broken = _BrokenVerifyVaultService(store);
    await broken.initialize();
    final brokenCapture = VaultCredentialCapture(vault: broken);
    await expectLater(
      brokenCapture.captureSsh(passwordProfile, password: 'new'),
      throwsA(isA<VaultCaptureException>()),
    );

    final reloaded = await _service(store: store);
    expect(
      await reloaded.readField((await reloaded.list()).single.id, 'password'),
      'old',
    );
  });

  test('rollback of an update restores the previous fields', () async {
    final store = _FakeStore();
    final service = await _service(store: store);
    final capture = VaultCredentialCapture(vault: service);
    await capture.captureSsh(passwordProfile, password: 'old');
    final updated = await capture.captureSsh(passwordProfile, password: 'new');
    expect(updated.created, isFalse);

    await capture.rollback(updated);
    expect(await service.readField(updated.entryId, 'password'), 'old');
  });
}

class _BrokenVerifyVaultService extends VaultService {
  _BrokenVerifyVaultService(_FakeStore store)
    : super(
        keychainBackend: KeychainVaultBackend(store),
        encryptedBackend: EncryptedVaultBackend(
          repository: VaultRepository(
            rootDir: '/root/vault',
            fs: InMemoryFilesystem(
              pathContext: p.Context(style: p.Style.posix),
            ),
          ),
          crypto: const VaultCrypto(
            memoryKiB: 256,
            iterations: 1,
            parallelism: 1,
          ),
        ),
      );

  @override
  Future<bool> verifyFields(String entryId, Map<String, String> fields) async =>
      false;
}
