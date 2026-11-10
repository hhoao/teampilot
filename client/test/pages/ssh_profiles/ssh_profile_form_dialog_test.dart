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
class RecordingRepository extends SshProfileRepository {
  RecordingRepository() : super(storage: fakeHomeStorage());

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

class EditorHarness {
  const EditorHarness({
    required this.deviceRepository,
    required this.planeRepository,
    required this.credentials,
    required this.deviceCubit,
    required this.planeCubit,
    required this.vault,
  });

  final RecordingRepository deviceRepository;
  final RecordingRepository planeRepository;
  final InMemorySshCredentialStore credentials;
  final SshProfileCubit deviceCubit;
  final SshProfileCubit planeCubit;
  final VaultService vault;
}

Future<EditorHarness> pumpEditor(
  WidgetTester tester, {
  SshProfile? profile,
}) async {
  final deviceRepository = RecordingRepository();
  final planeRepository = RecordingRepository();
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
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appLocalizationsSupportedLocales,
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
                          showSshProfileFormDialog(ctx, profile: profile),
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
  return EditorHarness(
    deviceRepository: deviceRepository,
    planeRepository: planeRepository,
    credentials: credentials,
    deviceCubit: deviceCubit,
    planeCubit: planeCubit,
    vault: vault,
  );
}

void main() {
  testWidgets('the dialog saves through the repository and cubit of the '
      'calling page', (tester) async {
    final h = await pumpEditor(tester, profile: _target);

    // Fields in build order: label, host, username, port, private key,
    // passphrase, password.
    await tester.enterText(find.byType(TextField).at(6), 'new-password');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    expect(h.planeRepository.saves.single.id, _target.id);
    expect(h.planeRepository.saves.single.vaultEntryId, isNotEmpty);
    expect(h.deviceRepository.saves, isEmpty);
    expect(h.planeCubit.state.profiles.single.id, _target.id);
    expect(h.deviceCubit.state.profiles, isEmpty);
    expect(
      await h.vault.readField(
        h.planeRepository.saves.single.vaultEntryId!,
        'password',
      ),
      'new-password',
    );
  });

  testWidgets('pastes a private key and saves it to the vault', (tester) async {
    final h = await pumpEditor(tester);
    const pem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n'
        '-----END OPENSSH PRIVATE KEY-----';

    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.enterText(find.byType(TextField).at(4), pem);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    final entryId = h.planeRepository.saves.single.vaultEntryId;
    expect(entryId, isNotNull);
    expect(await h.vault.readField(entryId!, 'privateKey'), pem);
  });

  testWidgets('reveals the saved password for a plane row with no vault link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final h = await pumpEditor(tester, profile: _target);
    await VaultCredentialCapture(vault: h.vault).captureSsh(
      _target,
      password: 's3cret',
    );

    // The dialog has two TpPasswordInput fields (passphrase, then password)
    // and both toggles share the same key. The password field is second.
    final toggles = find.byKey(const ValueKey('password-visibility-toggle'));
    expect(toggles, findsNWidgets(2));
    // The password field is last of seven; keep it in view before tapping.
    await tester.ensureVisible(toggles.at(1));
    await tester.pumpAndSettle();
    await tester.tap(toggles.at(1));
    await tester.pumpAndSettle();

    expect(find.text('s3cret'), findsOneWidget);
  });
}
