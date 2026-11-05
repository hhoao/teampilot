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

VaultService _buildVault(_FakeStore store, InMemoryFilesystem fs) =>
    VaultService(
      keychainBackend: KeychainVaultBackend(store),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );

Future<VaultService> _vault() async {
  final service = _buildVault(
    _FakeStore(),
    InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
  );
  await service.initialize();
  return service;
}

/// An unlocked writer and a second service over the same encrypted document
/// that starts locked, so a gate call would fail.
Future<(VaultService, VaultService)> _encryptedVaultPair() async {
  final store = _FakeStore();
  final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  final unlocked = _buildVault(store, fs);
  await unlocked.initialize();
  await unlocked.enableEncryptedBackend('pass');
  final locked = _buildVault(store, fs);
  await locked.initialize();
  return (unlocked, locked);
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
      existingValues: const {},
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
      existingValues: const {},
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    await saveManagedProviderWithVault(
      provider: first,
      existingValues: {'apiKey': 'a'},
      secretValues: {'secretKey': 'b'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );
    final entry = (await vault.get(first.vaultEntryId!))!;
    expect(entry.fields, {'apiKey': 'a', 'secretKey': 'b'});
  });

  test('carries legacy fields into a new vault entry', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);

    final saved = await saveManagedProviderWithVault(
      provider: provider,
      existingValues: {'apiKey': 'legacy'},
      secretValues: {'secretKey': 'new'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );

    final entry = (await vault.get(saved.vaultEntryId!))!;
    expect(entry.fields, {'apiKey': 'legacy', 'secretKey': 'new'});
  });

  test('empty secret values persist without touching the vault', () async {
    final (_, locked) = await _encryptedVaultPair();
    var prompted = false;
    ManagedProvider? persisted;

    final saved = await saveManagedProviderWithVault(
      provider: provider,
      existingValues: const {},
      secretValues: const {},
      capture: VaultCredentialCapture(vault: locked),
      unlockGate: VaultUnlockGate(
        vault: locked,
        prompt: () async {
          prompted = true;
          return true;
        },
      ),
      persist: (value) async => persisted = value,
    );

    expect(saved, same(provider));
    expect(persisted, same(provider));
    expect(prompted, isFalse);
  });

  test('persist failure rolls the capture back', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);

    await expectLater(
      saveManagedProviderWithVault(
        provider: provider,
        existingValues: const {},
        secretValues: {'apiKey': 'a'},
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        persist: (_) async => throw StateError('persist failed'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await vault.list(), isEmpty);
  });

  test('update persist failure restores the previous fields', () async {
    final vault = await _vault();
    final capture = VaultCredentialCapture(vault: vault);
    final first = await saveManagedProviderWithVault(
      provider: provider,
      existingValues: const {},
      secretValues: {'apiKey': 'a'},
      capture: capture,
      unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
      persist: (_) async {},
    );

    await expectLater(
      saveManagedProviderWithVault(
        provider: first,
        existingValues: {'apiKey': 'a'},
        secretValues: {'secretKey': 'b'},
        capture: capture,
        unlockGate: VaultUnlockGate(vault: vault, prompt: () async => true),
        persist: (_) async => throw StateError('persist failed'),
      ),
      throwsA(isA<StateError>()),
    );
    final entry = (await vault.get(first.vaultEntryId!))!;
    expect(entry.fields, {'apiKey': 'a'});
  });
}
