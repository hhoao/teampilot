import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/connect/paired_relay_tunnel_registry.dart';
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

void main() {
  test('reads the relay grant from the linked vault entry first', () async {
    final vault = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(
          rootDir: '/root/vault',
          fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
        ),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    await vault.initialize();
    await vault.upsert(
      const VaultEntry(
        id: 'v1',
        type: VaultEntryType.sshPassword,
        title: 'Paired',
        fields: {'relayGrant': 'vault-grant'},
      ),
    );
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'legacy-grant');
    const profile = SshProfile(
      id: 'p1',
      name: 'Paired',
      host: '127.0.0.1',
      username: 'u',
      vaultEntryId: 'v1',
    );
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: vault,
    );

    expect(await registry.relayGrantFor(profile), 'vault-grant');

    const legacy = SshProfile(
      id: 'p2',
      name: 'Legacy',
      host: '127.0.0.1',
      username: 'u',
    );
    expect(await registry.relayGrantFor(legacy), isNull);
  });
}
