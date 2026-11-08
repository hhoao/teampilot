import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profile_form_dialog.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/in_memory_filesystem.dart';

const _target = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

/// Records writes so the test can tell which catalog the editor wrote to.
class _RecordingRepository extends SshProfileRepository {
  _RecordingRepository() : super(storage: fakeHomeStorage());

  final saves = <SshProfile>[];
  SshProfile? stored;

  @override
  Future<void> save(SshProfile profile) async {
    saves.add(profile);
    stored = profile;
  }

  @override
  Future<List<SshProfile>> loadAll() async => [if (stored != null) stored!];

  @override
  Future<SshProfile?> findById(String profileId) async =>
      stored?.id == profileId ? stored : null;

  @override
  Future<String> loadSelectedProfileId() async => '';

  @override
  Future<void> saveSelectedProfileId(String profileId) async {}
}

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
  testWidgets('the dialog saves through the repository and cubit of the '
      'calling page', (tester) async {
    // Mirrors the "SSH servers" page: the app-level provider is device-local,
    // the page provides the home-plane catalog for its own subtree.
    final deviceRepository = _RecordingRepository();
    final planeRepository = _RecordingRepository();
    final credentials = InMemorySshCredentialStore();
    final deviceCubit = SshProfileCubit(
      profileRepository: deviceRepository,
      credentialStore: credentials,
    );
    final planeCubit = SshProfileCubit(
      profileRepository: planeRepository,
      credentialStore: credentials,
    );
    final vault = await _vault();
    addTearDown(deviceCubit.close);
    addTearDown(planeCubit.close);

    final theme = ThemeData(useMaterial3: true);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SshProfileRepository>.value(
            value: deviceRepository,
          ),
          RepositoryProvider<SshCredentialStore>.value(value: credentials),
          RepositoryProvider<VaultService>.value(value: vault),
          RepositoryProvider<VaultCredentialCapture>.value(
            value: VaultCredentialCapture(vault: vault),
          ),
          RepositoryProvider<VaultUnlockGate>.value(
            value: VaultUnlockGate(vault: vault, prompt: () async => true),
          ),
        ],
        child: BlocProvider<SshProfileCubit>.value(
          value: deviceCubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: theme,
            home: TpTheme(
              data: TpThemeData.fromColorScheme(
                theme.colorScheme,
                scale: 1.0,
                controlScale: AppTypographyScale.standard.multiplier,
              ),
              child: MultiRepositoryProvider(
                providers: [
                  RepositoryProvider<SshProfileRepository>.value(
                    value: planeRepository,
                  ),
                ],
                child: BlocProvider<SshProfileCubit>.value(
                  value: planeCubit,
                  child: Scaffold(
                    body: Builder(
                      builder: (ctx) => TextButton(
                        onPressed: () =>
                            showSshProfileFormDialog(ctx, profile: _target),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Fields in build order: label, host, username, port, key file,
    // passphrase, password.
    await tester.enterText(find.byType(TextField).at(6), 'new-password');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(planeRepository.saves, hasLength(1));
    expect(planeRepository.saves.single.id, _target.id);
    expect(planeRepository.saves.single.vaultEntryId, isNotEmpty);
    expect(deviceRepository.saves, isEmpty);
    expect(planeCubit.state.profiles.single.id, _target.id);
    expect(deviceCubit.state.profiles, isEmpty);
    expect(
      await vault.readField(
        planeRepository.saves.single.vaultEntryId!,
        'password',
      ),
      'new-password',
    );
  });
}
