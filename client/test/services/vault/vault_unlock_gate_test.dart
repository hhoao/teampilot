import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
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

VaultService _service() => VaultService(
  keychainBackend: KeychainVaultBackend(_FakeStore()),
  encryptedBackend: EncryptedVaultBackend(
    repository: VaultRepository(
      rootDir: '/root/vault',
      fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
    ),
    crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
  ),
);

void main() {
  test('unlocked vault skips the prompt', () async {
    final service = _service();
    await service.initialize();
    var prompts = 0;
    final gate = VaultUnlockGate(
      vault: service,
      prompt: () async {
        prompts++;
        return true;
      },
    );
    expect(await gate.ensureUnlocked(), isTrue);
    expect(prompts, 0);
  });

  test('refused prompt returns false', () async {
    final service = _service();
    await service.initialize();
    final gate = VaultUnlockGate(
      vault: _LockedVaultService(service),
      prompt: () async => false,
    );
    expect(await gate.ensureUnlocked(), isFalse);
  });
}

class _LockedVaultService implements VaultService {
  _LockedVaultService(this._delegate);

  final VaultService _delegate;

  @override
  bool get isEncrypted => _delegate.isEncrypted;

  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
