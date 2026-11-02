import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/provider_usage/managed_provider_vault_writer.dart';
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

Future<VaultService> _vault() async {
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

void main() {
  final provider = ManagedProvider(
    id: 'm1',
    name: 'Usage',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http_json_mapping',
  );

  test('captures secrets, links the provider and persists', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);
    ManagedProvider? persisted;

    final saved = await saveManagedProviderWithVault(
      provider: provider,
      current: null,
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (value) async => persisted = value,
    );

    expect(saved.vaultEntryId, isNotNull);
    expect(persisted?.vaultEntryId, saved.vaultEntryId);
    expect(await vault.readField(saved.vaultEntryId!, 'apiKey'), 'a');
  });

  test('merges existing fields on update', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);
    final first = await saveManagedProviderWithVault(
      provider: provider,
      current: null,
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    await saveManagedProviderWithVault(
      provider: first,
      current: first,
      secretValues: {'secretKey': 'b'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    final entry = (await vault.get(first.vaultEntryId!))!;
    expect(entry.fields, {'apiKey': 'a', 'secretKey': 'b'});
  });

  test('persist failure rolls the capture back', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);

    await expectLater(
      saveManagedProviderWithVault(
        provider: provider,
        current: null,
        secretValues: {'apiKey': 'a'},
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        persist: (_) async => throw StateError('persist failed'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });
}
