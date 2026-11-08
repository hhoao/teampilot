import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/pages/vault/vault_secret_reveal.dart';
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

void main() {
  late VaultService vault;
  late BuildContext context;

  setUp(() async {
    vault = VaultService(
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
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider<VaultService>.value(
        value: vault,
        child: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets('reveals the password owned by an SSH profile', (tester) async {
    await vault.upsert(
      const VaultEntry(
        id: 'entry-1',
        type: VaultEntryType.sshPassword,
        title: 'dev',
        fields: {'password': 's3cret'},
        extra: {'ownerKind': vaultOwnerKindSshProfile, 'ownerId': 'profile-1'},
      ),
    );
    await pumpHost(tester);

    final value = await revealVaultOwnerSecret(
      context,
      ownerKind: vaultOwnerKindSshProfile,
      ownerId: 'profile-1',
      field: 'password',
    );

    expect(value, 's3cret');
  });

  testWidgets('returns null when no entry belongs to the owner', (
    tester,
  ) async {
    await pumpHost(tester);

    final value = await revealVaultOwnerSecret(
      context,
      ownerKind: vaultOwnerKindSshProfile,
      ownerId: 'missing',
      field: 'password',
    );

    expect(value, isNull);
  });
}
