import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/vault/vault_entry_editor.dart';
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
  testWidgets('saves a new entry with a title and secret field', (
    tester,
  ) async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final cubit = VaultCubit(
      service: VaultService(
        keychainBackend: KeychainVaultBackend(_FakeStore()),
        encryptedBackend: EncryptedVaultBackend(
          repository: VaultRepository(rootDir: '/root/vault', fs: fs),
          crypto: const VaultCrypto(
            memoryKiB: 256,
            iterations: 1,
            parallelism: 1,
          ),
        ),
      ),
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: VaultEntryEditorDialog()),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('vault-editor-title')),
      'OpenAI',
    );
    await tester.tap(find.byKey(const Key('vault-editor-save')));
    await tester.pumpAndSettle();

    expect(cubit.state.entries.single.title, 'OpenAI');
  });
}
