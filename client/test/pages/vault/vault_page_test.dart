import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/pages/vault/vault_entry_list.dart';
import 'package:teampilot/pages/vault/vault_page.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
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
  testWidgets('lists entries and filters by query', (tester) async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final service = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    final cubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.login, title: 'GitHub'),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(body: VaultEntryList(onOpen: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
  });

  testWidgets('page loads the vault on first mount', (tester) async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = KeychainVaultBackend(_FakeStore());
    await backend.save(
      const VaultDocument(
        entries: [
          VaultEntry(id: 'a', type: VaultEntryType.login, title: 'GitHub'),
        ],
      ),
    );
    final service = VaultService(
      keychainBackend: backend,
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    final cubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: VaultPageBody()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
  });
}
