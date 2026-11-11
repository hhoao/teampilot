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
import 'package:teampilot/theme/app_outline_input_theme.dart';
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
  bool appInputTheme = false,
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

  final baseTheme = ThemeData(useMaterial3: true);
  final tpThemeData = TpThemeData.fromColorScheme(
    baseTheme.colorScheme,
    scale: 1.0,
    controlScale: AppTypographyScale.standard.multiplier,
  );
  final theme = appInputTheme
      ? baseTheme.copyWith(
          inputDecorationTheme: buildAppOutlineInputDecorationTheme(
            colorScheme: baseTheme.colorScheme,
            textTheme: baseTheme.textTheme,
            control: tpThemeData.control,
          ),
        )
      : baseTheme;
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
            data: tpThemeData,
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

    // Fields in build order: label, host, username, port, password.
    await tester.enterText(find.byType(TextField).at(4), 'new-password');
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
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();
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

    // The dialog has a single TpPasswordInput in password mode: the password
    // field. Its reveal toggle is the one to tap.
    final toggles = find.byKey(const ValueKey('password-visibility-toggle'));
    expect(toggles, findsOneWidget);
    await tester.ensureVisible(toggles);
    await tester.pumpAndSettle();
    await tester.tap(toggles);
    await tester.pumpAndSettle();

    expect(find.text('s3cret'), findsOneWidget);
  });

  testWidgets('private key field stays multiline under the app single-line '
      'input theme', (tester) async {
    await pumpEditor(tester, appInputTheme: true);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();

    // Build order: label, host, username, port, private key, passphrase.
    // The global outline theme pins every TextField to a 32dp single-line
    // track; the private key field must opt out so a pasted PEM is actually
    // visible.
    final privateKey = find.byType(TextField).at(4);
    expect(tester.getSize(privateKey).height, greaterThan(48));
  });

  testWidgets('defaults to password mode and hides the key fields', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);
    expect(find.text('Key passphrase'), findsNothing);
    expect(find.text('Login password'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    expect(find.text('Key passphrase'), findsOneWidget);
    expect(find.text('Login password'), findsNothing);
  });

  testWidgets('edit initializes the mode from the profile auth type', (
    tester,
  ) async {
    const keyed = SshProfile(
      id: 'p2',
      name: 'keyed',
      host: 'example.com',
      username: 'alice',
      authType: SshAuthType.privateKey,
    );
    await pumpEditor(tester, profile: keyed);

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    expect(find.text('Key passphrase'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Password'),
      ),
    );
    await tester.pumpAndSettle();

    // Switching modes means no stored password applies, so the hint is the
    // plain one rather than "leave empty to keep saved password".
    expect(find.text('Login password'), findsOneWidget);
    expect(find.text('Leave empty to keep saved password'), findsNothing);
    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);
  });

  testWidgets('creating a password target requires a password', (tester) async {
    final h = await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).at(1), 'example.com');

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, isEmpty);

    // Dismiss the warning toast so its auto-close timer does not outlive the
    // widget tree (same pattern as app_toast_recorder_test.dart).
    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('creating a private-key target requires a key', (tester) async {
    final h = await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, isEmpty);

    // Dismiss the warning toast so its auto-close timer does not outlive the
    // widget tree (same pattern as app_toast_recorder_test.dart).
    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('switching auth mode on edit requires confirmation', (
    tester,
  ) async {
    final h = await pumpEditor(tester, profile: _target);
    await VaultCredentialCapture(vault: h.vault).captureSsh(
      _target,
      password: 'old-pass',
    );
    const pem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n'
        '-----END OPENSSH PRIVATE KEY-----';

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(4), pem);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Switch authentication?'), findsOneWidget);
    expect(
      find.text(
        'Saving will remove the credential stored for the other authentication method.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ssh-auth-change-cancel')));
    await tester.pumpAndSettle();
    expect(h.planeRepository.saves, isEmpty);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ssh-auth-change-confirm')));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    expect(h.planeRepository.saves.single.authType, SshAuthType.privateKey);
    final entryId = h.planeRepository.saves.single.vaultEntryId!;
    expect(await h.vault.readField(entryId, 'privateKey'), pem);
    expect(await h.vault.readField(entryId, 'password'), isNull);
  });

  testWidgets('switching to password on edit requires a password', (
    tester,
  ) async {
    const keyed = SshProfile(
      id: 'p3',
      name: 'keyed',
      host: 'example.com',
      username: 'alice',
      authType: SshAuthType.privateKey,
    );
    final h = await pumpEditor(tester, profile: keyed);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Password'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Switch authentication?'), findsNothing);
    expect(h.planeRepository.saves, isEmpty);
    // Dismiss the warning toast so its auto-close timer does not outlive the
    // widget tree (same pattern as app_toast_recorder_test.dart).
    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('typed credentials survive a mode round-trip', (tester) async {
    await pumpEditor(tester, profile: _target);
    await tester.enterText(find.byType(TextField).at(4), 'typed-pass');

    final control = find.byKey(const ValueKey('ssh-auth-type'));
    await tester.tap(
      find.descendant(of: control, matching: find.text('Private key')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: control, matching: find.text('Password')),
    );
    await tester.pumpAndSettle();

    expect(find.text('typed-pass'), findsOneWidget);
  });
}
