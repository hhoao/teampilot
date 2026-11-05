import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/connect/paired_relay_tunnel_registry.dart';
import 'package:teampilot/services/connect/phone_relay_tunnel.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_access.dart';
import 'package:teampilot/services/vault/vault_service.dart';

import '../../support/in_memory_filesystem.dart';
import 'embedded_ssh_server_test.dart' show testDevicePem;

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RecordingTunnel extends PhoneRelayTunnel {
  String? grant;
  bool opened = false;

  @override
  bool get isClosed => !opened;

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  int get port => 1234;

  @override
  Future<void> open({
    required Uri relayUrl,
    required String hostId,
    required String channel,
    String? deviceId,
    String? inviteToken,
    String? relayGrant,
  }) async {
    opened = true;
    grant = relayGrant;
  }

  @override
  Future<void> close() async {
    opened = false;
  }
}

VaultService _newVault() => VaultService(
  keychainBackend: KeychainVaultBackend(_FakeStore()),
  encryptedBackend: EncryptedVaultBackend(
    repository: VaultRepository(
      rootDir: '/root/vault',
      fs: InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
    ),
    crypto: const VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1),
  ),
);

const _pairedProfile = SshProfile(
  id: 'p1',
  name: 'Paired',
  host: '127.0.0.1',
  username: 'u',
  pairedDesktopId: 'desktop-1',
  relayUrl: 'ws://127.0.0.1:9999/relay',
  vaultEntryId: 'v1',
);

const _legacyProfile = SshProfile(
  id: 'p2',
  name: 'Legacy',
  host: '127.0.0.1',
  username: 'u',
);

void main() {
  test('reads the relay grant from the linked vault entry first', () async {
    final vault = _newVault();
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
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: VaultAccess(vault),
    );

    expect(await registry.relayGrantFor(_pairedProfile), 'vault-grant');
    expect(await registry.relayGrantFor(_legacyProfile), isNull);
  });

  test('falls back to the keychain grant when the vault is locked', () async {
    final vault = _newVault();
    await vault.initialize();
    await vault.enableEncryptedBackend('passphrase');
    vault.lock();
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'keychain-grant');
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: VaultAccess(vault),
    );

    expect(await registry.relayGrantFor(_pairedProfile), 'keychain-grant');
  });

  test('falls back to the keychain grant when the entry has none', () async {
    final vault = _newVault();
    await vault.initialize();
    await vault.upsert(
      const VaultEntry(
        id: 'v1',
        type: VaultEntryType.sshPassword,
        title: 'Paired',
        fields: {'host': '127.0.0.1', 'username': 'u'},
      ),
    );
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'keychain-grant');
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: VaultAccess(vault),
    );

    expect(await registry.relayGrantFor(_pairedProfile), 'keychain-grant');
  });

  test('uses the keychain grant when no vault is configured', () async {
    final credentials = InMemorySshCredentialStore();
    await credentials.saveRelayGrant('p1', 'keychain-grant');
    final registry = PairedRelayTunnelRegistry(credentialStore: credentials);

    expect(await registry.relayGrantFor(_pairedProfile), 'keychain-grant');
  });

  test('ensureSshTunnel dials with the vault grant', () async {
    final vault = _newVault();
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
    await credentials.saveDevicePrivateKey(testDevicePem);
    await credentials.saveRelayGrant('p1', 'keychain-grant');
    final tunnel = _RecordingTunnel();
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: VaultAccess(vault),
      tunnelFactory: () => tunnel,
    );

    final target = await registry.ensureSshTunnel(_pairedProfile);

    expect(tunnel.opened, isTrue);
    expect(tunnel.grant, 'vault-grant');
    expect(target.port, 1234);
  });

  test('ensureSshTunnel dials with the keychain grant when locked', () async {
    final vault = _newVault();
    await vault.initialize();
    await vault.enableEncryptedBackend('passphrase');
    vault.lock();
    final credentials = InMemorySshCredentialStore();
    await credentials.saveDevicePrivateKey(testDevicePem);
    await credentials.saveRelayGrant('p1', 'keychain-grant');
    final tunnel = _RecordingTunnel();
    final registry = PairedRelayTunnelRegistry(
      credentialStore: credentials,
      vault: VaultAccess(vault),
      tunnelFactory: () => tunnel,
    );

    await registry.ensureSshTunnel(_pairedProfile);

    expect(tunnel.grant, 'keychain-grant');
  });
}
