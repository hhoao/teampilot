import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_link_binding.dart';
import 'package:teampilot/services/provider/credential_login_progress.dart';
import 'package:teampilot/services/provider/provider_import_service.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../support/in_memory_filesystem.dart';

class _SpyProviderImportService extends ProviderImportService {
  _SpyProviderImportService()
    : super(
        repository: AppProviderRepository(storage: fakeHomeStorage()),
        storage: fakeHomeStorage(),
      );

  var importAllCalls = 0;
  final importForCliCalls = <CliTool>[];

  @override
  Future<List<ProviderImportResult>> importAllCatalogClis({
    required bool onlyIfEmpty,
  }) async {
    importAllCalls++;
    return [
      const ProviderImportResult(cli: CliTool.claude, added: 1),
      const ProviderImportResult(cli: CliTool.codex, added: 1),
    ];
  }

  @override
  Future<ProviderImportResult> importForCli(
    CliTool cli, {
    required bool onlyIfEmpty,
  }) async {
    importForCliCalls.add(cli);
    return ProviderImportResult(cli: cli, added: 1);
  }
}

void main() {
  late Directory temp;
  late AppProviderCubit cubit;
  late AppProviderRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app_provider_cubit_');
    repository = AppProviderRepository(
      basePath: temp.path,
      storage: fakeHomeStorage(),
    );
    cubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('rejects a credentialLink that a managed entry links back to', () async {
    final managedRepo = ManagedProviderRepository(
      storage: fakeHomeStorage(),
      configPath: '${temp.path}${Platform.pathSeparator}managed-providers.json',
      onProvidersDeleted: (_) async {},
    );
    await managedRepo.upsert(
      ManagedProvider(
        id: 'm1',
        name: 'M1',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'http-json',
        endpointConfig: ManagedProviderEndpointConfig(
          credentialSource: managedProviderLinkSourceValue(
            CliTool.claude,
            'deepseek',
          ),
        ),
      ),
    );
    final guardedCubit = AppProviderCubit(
      storage: fakeHomeStorage(),
      repository: repository,
      basePath: temp.path,
      managedProviderRepository: managedRepo,
    );
    addTearDown(guardedCubit.close);

    final saved = await guardedCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
        credentialLink: 'm1',
      ),
    );
    expect(saved, isFalse);
    expect(guardedCubit.state.providersFor(CliTool.claude), isEmpty);

    // The same row without a conflicting managed entry persists fine.
    final ok = await guardedCubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.claude,
        name: 'DeepSeek',
        category: AppProviderCategory.thirdParty,
      ),
    );
    expect(ok, isTrue);
    expect(guardedCubit.state.providersFor(CliTool.claude), isNotEmpty);
    await managedRepo.delete('m1');
  });

  test('importAllFromExternal imports every catalog CLI', () async {
    final spy = _SpyProviderImportService();
    final allCliCubit = AppProviderCubit(
      repository: repository,
      importService: spy,
      basePath: temp.path,
      storage: fakeHomeStorage(),
    );
    addTearDown(allCliCubit.close);

    await repository.saveProviders(CliTool.claude, const [
      AppProviderConfig(id: 'claude-a', cli: CliTool.claude, name: 'Claude A'),
    ]);
    await repository.saveProviders(CliTool.codex, const [
      AppProviderConfig(id: 'codex-a', cli: CliTool.codex, name: 'Codex A'),
    ]);

    final results = await allCliCubit.importAllFromExternal();

    expect(spy.importAllCalls, 1);
    expect(spy.importForCliCalls, isEmpty);
    expect(
      results.map((r) => r.cli),
      containsAll([CliTool.claude, CliTool.codex]),
    );
    expect(
      allCliCubit.state.providersFor(CliTool.claude).single.id,
      'claude-a',
    );
    expect(allCliCubit.state.providersFor(CliTool.codex).single.id, 'codex-a');
    expect(allCliCubit.state.statusMessage, contains('Imported'));
  });

  test('deleteProvider selects next provider within current cli', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(id: 'a', cli: CliTool.claude, name: 'A'),
    );
    await cubit.upsertProvider(
      const AppProviderConfig(id: 'b', cli: CliTool.claude, name: 'B'),
    );
    cubit.selectProvider('a');

    await cubit.deleteProvider('a');

    expect(cubit.state.selectedId, 'b');
    expect(cubit.state.providers.map((p) => p.id), ['b']);
  });

  test(
    'saving a form draft does not clobber probed credential status',
    () async {
      // Row probed ready by a successful login inside the add form.
      const ready = AppProviderConfig(
        id: 'openai-official-2',
        cli: CliTool.codex,
        name: 'OpenAI Official',
        category: AppProviderCategory.official,
        isOfficial: true,
        credentialStatus: 'ready',
        credentialUpdatedAt: 123,
      );
      await cubit.upsertProvider(ready);

      // The add-form draft carries no probe info (missing / 0), like
      // AppProviderFormSheet._buildNormalDraft.
      const draft = AppProviderConfig(
        id: 'openai-official-2',
        cli: CliTool.codex,
        name: 'OpenAI Official',
        category: AppProviderCategory.official,
        isOfficial: true,
      );
      await cubit.upsertProvider(draft);

      final saved = cubit.state.providersFor(CliTool.codex).single;
      expect(saved.credentialStatus, 'ready');
      expect(saved.credentialUpdatedAt, 123);
    },
  );

  test('probe-driven downgrade still clears credential status', () async {
    const ready = AppProviderConfig(
      id: 'openai-official-2',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      credentialStatus: 'ready',
      credentialUpdatedAt: 123,
    );
    await cubit.upsertProvider(ready);

    // Revoke path: withCredentialProbe on a missing probe keeps the old
    // credentialUpdatedAt (> 0) but downgrades the status.
    const revoked = AppProviderConfig(
      id: 'openai-official-2',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.official,
      isOfficial: true,
      credentialStatus: 'missing',
      credentialUpdatedAt: 123,
    );
    await cubit.upsertProvider(revoked);

    expect(
      cubit.state.providersFor(CliTool.codex).single.credentialStatus,
      'missing',
    );
  });

  test('switching cli restores selected provider for that cli', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'claude-provider',
        cli: CliTool.claude,
        name: 'Claude Provider',
      ),
    );
    await cubit.setSelectedCli(CliTool.codex);
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'codex-provider',
        cli: CliTool.codex,
        name: 'Codex Provider',
      ),
    );

    await cubit.setSelectedCli(CliTool.claude);
    expect(cubit.state.selectedCli, CliTool.claude);
    expect(cubit.state.selectedId, 'claude-provider');

    await cubit.setSelectedCli(CliTool.codex);
    expect(cubit.state.selectedCli, CliTool.codex);
    expect(cubit.state.selectedId, 'codex-provider');
  });

  test('flashskyai models provider is normalized to provider id', () async {
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'deepseek',
        cli: CliTool.flashskyai,
        name: 'DeepSeek',
        config: {
          'models': {
            'deepseek-chat': {
              'name': 'deepseek-chat',
              'provider': 'DeepSeek',
              'model': 'deepseek-chat',
              'enabled': true,
            },
          },
        },
      ),
    );

    final saved = (await repository.loadProviders(CliTool.flashskyai)).single;
    final models = saved.config['models'] as Map;
    final model = models['deepseek-chat'] as Map;
    expect(model['provider'], 'deepseek');
  });

  test(
    'reportCredentialLoginProgress stores device code for the waiting UI',
    () {
      cubit.beginCredentialLogin('openai-official');
      cubit.reportCredentialLoginProgress(
        CredentialLoginProgress(
          deviceCode: 'WO3M-X8OIF',
          verificationUri: Uri.parse('https://auth.openai.com/codex/device'),
        ),
      );

      expect(cubit.state.credentialLoginProviderId, 'openai-official');
      expect(cubit.state.credentialLoginDeviceCode, 'WO3M-X8OIF');
      expect(
        cubit.state.credentialLoginVerificationUri,
        'https://auth.openai.com/codex/device',
      );

      cubit.clearCredentialLoginProgress();
      expect(cubit.state.credentialLoginDeviceCode, isNull);
      expect(cubit.state.credentialLoginProviderId, isNull);
    },
  );

  test('prospectiveIdForNewProvider uses preset id not display name', () {
    const presets = [
      AppProviderPreset(
        id: 'opencode-go',
        label: 'OpenCode Go',
        template: AppProviderConfig(
          id: 'opencode-go',
          cli: CliTool.opencode,
          name: 'OpenCode Go',
        ),
      ),
    ];
    expect(
      AppProviderCubit.prospectiveIdForNewProvider(
        presetId: 'opencode-go',
        presets: presets,
        displayName: 'Opencode Go Google',
        existingIds: const ['opencode-go'],
      ),
      'opencode-go-2',
    );
  });

  test('saving a key captures it in the vault and clears the plaintext', () async {
    final vault = await _vaultService();
    final capture = VaultCredentialCapture(vault: vault);
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: capture,
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const draft = AppProviderConfig(
      id: 'captured',
      cli: CliTool.claude,
      name: 'Captured',
      apiKey: 'sk-secret',
    );
    expect(
      await autoCubit.upsertProvider(
        draft,
        captureVaultCredentials: true,
      ),
      isTrue,
    );

    final saved = autoCubit.state.providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'captured');
    expect(saved.apiKey, isEmpty);
    expect(saved.credentialLink, startsWith('vault:'));
    final entryId = saved.credentialLink.substring('vault:'.length);
    expect(await vault.readField(entryId, 'apiKey'), 'sk-secret');

    await autoCubit.deleteProvider('captured');
    expect(await vault.get(entryId), isNull);
  });

  test('background upserts never capture or prompt', () async {
    final vault = await _vaultService();
    var prompts = 0;
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async {
        prompts++;
        return true;
      },
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const linked = AppProviderConfig(
      id: 'linked',
      cli: CliTool.claude,
      name: 'Linked',
      apiKey: 'resolved-in-memory',
      credentialLink: 'm1',
    );
    expect(await autoCubit.upsertProvider(linked), isTrue);
    final saved = autoCubit.state.providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'linked');
    expect(saved.credentialLink, 'm1');
    expect(saved.apiKey, 'resolved-in-memory');
    expect(await vault.list(), isEmpty);
    expect(prompts, 0);

    const unlinked = AppProviderConfig(
      id: 'unlinked',
      cli: CliTool.claude,
      name: 'Unlinked',
      apiKey: 'plain',
    );
    expect(await autoCubit.upsertProvider(unlinked), isTrue);
    final persisted = autoCubit.state.providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'unlinked');
    expect(persisted.apiKey, 'plain');
    expect(await vault.list(), isEmpty);
    expect(prompts, 0);
  });

  test('dropping a managed link never persists the resolved key', () async {
    final vault = await _vaultService();
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const linked = AppProviderConfig(
      id: 'linked',
      cli: CliTool.claude,
      name: 'Linked',
      credentialLink: 'm1',
    );
    await autoCubit.upsertProvider(linked);
    final resolved = linked.copyWith(apiKey: 'resolved', credentialLink: '');
    await autoCubit.upsertProvider(resolved);
    final saved = autoCubit.state.providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'linked');
    expect(saved.apiKey, isEmpty);
  });

  test('same provider id in two CLIs keeps separate vault entries', () async {
    final vault = await _vaultService();
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const claudeRow = AppProviderConfig(
      id: 'shared',
      cli: CliTool.claude,
      name: 'Shared',
      apiKey: 'claude-key',
    );
    const codexRow = AppProviderConfig(
      id: 'shared',
      cli: CliTool.codex,
      name: 'Shared',
      apiKey: 'codex-key',
    );
    await autoCubit.upsertProvider(
      claudeRow,
      captureVaultCredentials: true,
    );
    await autoCubit.upsertProvider(codexRow, captureVaultCredentials: true);
    final entries = await vault.list();
    expect(entries, hasLength(2));
    expect(
      entries.map((entry) => entry.fields['apiKey']).toSet(),
      {'claude-key', 'codex-key'},
    );

    await autoCubit.setSelectedCli(CliTool.claude);
    await autoCubit.deleteProvider('shared');
    expect((await vault.list()).single.fields['apiKey'], 'codex-key');
  });

  test('a failed catalog save rolls the provider capture back', () async {
    final vault = await _vaultService();
    final throwing = _ThrowingSaveRepository(
      basePath: temp.path,
      storage: fakeHomeStorage(),
    );
    final autoCubit = AppProviderCubit(
      repository: throwing,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();
    throwing.failSaves = true;
    const draft = AppProviderConfig(
      id: 'rollback',
      cli: CliTool.claude,
      name: 'Rollback',
      apiKey: 'sk-rollback',
    );

    await expectLater(
      autoCubit.upsertProvider(draft, captureVaultCredentials: true),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });

  test('a failed catalog save keeps the vault entry on delete', () async {
    final vault = await _vaultService();
    final throwing = _ThrowingSaveRepository(
      basePath: temp.path,
      storage: fakeHomeStorage(),
    );
    final autoCubit = AppProviderCubit(
      repository: throwing,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();
    const row = AppProviderConfig(
      id: 'keep',
      cli: CliTool.claude,
      name: 'Keep',
      apiKey: 'k',
    );
    await autoCubit.upsertProvider(row, captureVaultCredentials: true);
    final entryId = autoCubit.state
        .providersFor(CliTool.claude)
        .firstWhere((p) => p.id == 'keep')
        .credentialLink
        .substring('vault:'.length);

    throwing.failSaves = true;
    await expectLater(
      autoCubit.deleteProvider('keep'),
      throwsA(isA<StateError>()),
    );
    expect(await vault.get(entryId), isNotNull);
  });

  test('removeProviderRow deletes the vault entry best-effort', () async {
    final vault = await _vaultService();
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: vault),
      ensureVaultUnlocked: () async => true,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const draft = AppProviderConfig(
      id: 'row',
      cli: CliTool.claude,
      name: 'Row',
      apiKey: 'sk-row',
    );
    expect(
      await autoCubit.upsertProvider(
        draft,
        captureVaultCredentials: true,
      ),
      isTrue,
    );
    final saved = autoCubit.state.providersFor(CliTool.claude).single;
    final entryId = saved.credentialLink.substring('vault:'.length);
    expect(await vault.get(entryId), isNotNull);

    await autoCubit.removeProviderRow(CliTool.claude, 'row');

    expect(autoCubit.state.providersFor(CliTool.claude), isEmpty);
    expect(await vault.get(entryId), isNull);
  });

  test('a refused unlock aborts the save', () async {
    final vault = await _vaultService();
    final autoCubit = AppProviderCubit(
      repository: repository,
      basePath: temp.path,
      storage: fakeHomeStorage(),
      vaultCapture: VaultCredentialCapture(vault: _LockedVaultService(vault)),
      ensureVaultUnlocked: () async => false,
    );
    addTearDown(autoCubit.close);
    await autoCubit.load();

    const draft = AppProviderConfig(
      id: 'blocked',
      cli: CliTool.claude,
      name: 'Blocked',
      apiKey: 'sk-secret',
    );
    expect(
      await autoCubit.upsertProvider(
        draft,
        captureVaultCredentials: true,
      ),
      isFalse,
    );
    expect(autoCubit.state.providersFor(CliTool.claude), isEmpty);
  });
}

Future<VaultService> _vaultService() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeVaultStore()),
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

class _ThrowingSaveRepository extends AppProviderRepository {
  _ThrowingSaveRepository({required super.basePath, required super.storage});

  bool failSaves = false;

  @override
  Future<void> saveProviders(CliTool cli, List<AppProviderConfig> providers) {
    if (failSaves) throw StateError('save failed');
    return super.saveProviders(cli, providers);
  }
}

class _FakeVaultStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LockedVaultService implements VaultService {
  _LockedVaultService(this._delegate);

  final VaultService _delegate;

  @override
  bool get isUnlocked => false;

  @override
  Future<void> delete(String id) => _delegate.delete(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
