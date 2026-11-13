import '../support/ssh_connectivity_test_harness.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/cubits/termux_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/remote_connections_page.dart';
import 'package:teampilot/pages/ssh_profiles_page.dart';
import 'package:teampilot/pages/startup_gate.dart';
import 'package:teampilot/pages/termux/work_environment_chooser_page.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';
import 'package:teampilot/services/ssh/android_ssh_connect_home.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/vault/credential_capture.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../support/in_memory_filesystem.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

class _ControllableSshConnectionCubit extends SshConnectionCubit {
  _ControllableSshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
  }) : super(
        factory: factory,
        coordinator: coordinator,
        connectivity: TestSshConnectivity(),
      );

  @override
  Future<void> connect(String profileId, {bool switchHome = true}) async {}

  @override
  Future<void> disconnect(String profileId) async {}
}

class _SeededSshProfileCubit extends SshProfileCubit {
  _SeededSshProfileCubit({
    required super.profileRepository,
    required super.credentialStore,
    required List<SshProfile> profiles,
  }) {
    emit(
      SshProfileState(
        profiles: profiles,
        selectedProfileId: profiles.isEmpty ? '' : profiles.first.id,
        isLoading: false,
      ),
    );
  }
}

class _Harness {
  _Harness() {
    events = SshConnectionEvents();
    credentialStore = InMemorySshCredentialStore();
    knownHosts = InMemorySshKnownHostRepository();
    factory = SshClientFactory(
      credentialStore: credentialStore,
      knownHostRepository: knownHosts,
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
  }

  late final SshConnectionEvents events;
  late final InMemorySshCredentialStore credentialStore;
  late final InMemorySshKnownHostRepository knownHosts;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;

  _ControllableSshConnectionCubit createConnectionCubit() {
    return _ControllableSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
  }

  Future<void> dispose() => coordinator.dispose();
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future get done async {}
}

class _FakeVaultStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Unlocked in-memory vault so profile saves capture credentials like prod.
Future<VaultService> _unlockedVault() async {
  final service = VaultService(
    keychainBackend: KeychainVaultBackend(_FakeVaultStore()),
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

Future<Widget> _gateHost({
  required ConnectionModeService mode,
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required TerminalTransportFactory transportFactory,
  required SshProfileRepository profileRepository,
  required SessionPreferencesCubit sessionPrefs,
  required TermuxCubit termuxCubit,
  HomeConnectionCubit? homeConnectionCubit,
  bool? isAndroid,
  Widget child = const Text('APP_CHILD'),
}) async {
  final theme = ThemeData(useMaterial3: true);
  final vault = await _unlockedVault();
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>.value(value: mode),
      RepositoryProvider<SshCredentialStore>.value(value: credentialStore),
      RepositoryProvider<TerminalTransportFactory>.value(
        value: transportFactory,
      ),
      RepositoryProvider<SshProfileRepository>.value(value: profileRepository),
      RepositoryProvider<VaultCredentialCapture>.value(
        value: VaultCredentialCapture(vault: vault),
      ),
      RepositoryProvider<VaultUnlockGate>.value(
        value: VaultUnlockGate(vault: vault, prompt: () async => true),
      ),
      RepositoryProvider<VaultService>.value(value: vault),
    ],
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
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SshProfileCubit>.value(value: profileCubit),
            BlocProvider<SshConnectionCubit>.value(value: connectionCubit),
            BlocProvider<SessionPreferencesCubit>.value(value: sessionPrefs),
            BlocProvider<TermuxCubit>.value(value: termuxCubit),
            if (homeConnectionCubit != null)
              BlocProvider<HomeConnectionCubit>.value(
                value: homeConnectionCubit,
              ),
          ],
          child: StartupGate(isAndroid: isAndroid, child: child),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;
  late SshProfileRepository profileRepository;
  late _Harness harness;
  late _ControllableSshConnectionCubit connectionCubit;
  late SshProfileCubit profileCubit;
  late TerminalTransportFactory transportFactory;
  late SessionPreferencesCubit sessionPrefs;
  late Directory termuxNativeDir;
  late TermuxCubit termuxCubit;
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('startup_gate_');
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      fs: InMemoryFilesystem(),
      storage: fakeHomeStorage(),
    );

    harness = _Harness();
    connectionCubit = harness.createConnectionCubit();
    profileCubit = SshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
    );
    transportFactory = TerminalTransportFactory(
      sshProfileRepository: profileRepository,
      sshCredentialStore: harness.credentialStore,
      sshKnownHostRepository: harness.knownHosts,
      sshClientFactory: harness.factory,
    );
    final prefs = await SharedPreferences.getInstance();
    sessionPrefs = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    await sessionPrefs.load();
    termuxNativeDir = await Directory.systemTemp.createTemp(
      'startup_gate_termux_',
    );
    termuxCubit = TermuxCubit(
      store: TermuxConfigStore(
        rootDir: termuxNativeDir.path,
        fs: LocalFilesystem(
          pathContext: AppPaths.pathContextForDataRoot(termuxNativeDir.path),
        ),
      ),
      credentials: harness.credentialStore,
      nativeAppDataPath: termuxNativeDir.path,
      selectHome: (_) async {},
      testConnect: (_) async => (ok: true, message: ''),
    );
    l10n = await const AppLocalizationsCompatDelegate().load(
      const Locale('en'),
    );
  });

  tearDown(() async {
    await connectionCubit.close();
    await profileCubit.close();
    await termuxCubit.close();
    await sessionPrefs.close();
    await harness.dispose();
    await tempDir.delete(recursive: true);
    if (await termuxNativeDir.exists()) {
      await termuxNativeDir.delete(recursive: true);
    }
  });

  Future<void> pumpGatedEmptyList(WidgetTester tester) async {
    final mode = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );
    await tester.pumpWidget(
      await _gateHost(
        mode: mode,
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('gated startup shows SSH list, not bare setup title', (
    tester,
  ) async {
    await pumpGatedEmptyList(tester);

    expect(find.text('新增 SSH Profile'), findsNothing);
    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);
  });

  testWidgets('editor dialog opens and closing it returns to the list', (
    tester,
  ) async {
    await pumpGatedEmptyList(tester);

    final ctx = tester.element(find.byType(RemoteConnectionsPage));
    // Do not await: the future completes only after the dialog pops.
    final editor = openSshProfileEditor(
      ctx,
      repository: profileRepository,
      profileCubit: profileCubit,
      onRefresh: () => profileCubit.load(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TpDialogPageShell), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await editor;
    expect(find.byType(TpDialogPageShell), findsNothing);
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);
  });

  testWidgets('save does not clear gate', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mode = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.local,
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );
    await tester.pumpWidget(
      await _gateHost(
        mode: mode,
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.text('On-device · Termux'), findsOneWidget);
    expect(find.text('Remote · SSH'), findsOneWidget);

    await tester.tap(find.text('Remote · SSH'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);

    final ctx = tester.element(find.byType(RemoteConnectionsPage));
    // ignore: unawaited_futures — completes when the dialog pops
    openSshProfileEditor(
      ctx,
      repository: profileRepository,
      profileCubit: profileCubit,
      onRefresh: () => profileCubit.load(),
    );
    await tester.pumpAndSettle();

    // Password-mode dialog field order: label(0), host(1), username(2),
    // port(3), password(4).
    await tester.enterText(find.byType(TextField).at(0), 'My Box');
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.enterText(find.byType(TextField).at(2), 'alice');
    await tester.enterText(find.byType(TextField).at(4), 'password123');

    await tester.tap(
      find.descendant(
        of: find.byType(TpDialogPageShell),
        matching: find.text('Add target'),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && profileCubit.state.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(find.text('APP_CHILD'), findsNothing);
    expect(profileCubit.state.hasProfiles, isTrue);
    expect(find.byType(RemoteConnectionsPage), findsOneWidget);
  });

  testWidgets('after home becomes ssh:*, rebuilding gate shows child', (
    tester,
  ) async {
    var homeId = 'local';
    RuntimeTarget current() => homeId == 'local'
        ? RuntimeTarget.local()
        : RuntimeTarget.ssh('p1', label: 'box');

    await profileCubit.close();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );

    Future<Widget> host() => _gateHost(
      mode: ConnectionModeService(
        defaultTargetResolver: current,
        hasSshProfiles: () => profileCubit.state.hasProfiles,
      ),
      profileCubit: profileCubit,
      connectionCubit: connectionCubit,
      credentialStore: harness.credentialStore,
      transportFactory: transportFactory,
      profileRepository: profileRepository,
      sessionPrefs: sessionPrefs,
      termuxCubit: termuxCubit,
      isAndroid: true,
    );

    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.byType(WorkEnvironmentChooserPage), findsOneWidget);

    await applyAndroidSshConnectHome(
      profileId: 'p1',
      selectHome: (id) async => homeId = id,
      selectProfile: (_) async {},
    );

    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsOneWidget);
  });

  testWidgets('Android with local home shows work environment chooser', (
    tester,
  ) async {
    final mode = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.local,
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );
    await tester.pumpWidget(
      await _gateHost(
        mode: mode,
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.text('On-device · Termux'), findsOneWidget);
    expect(find.text('Remote · SSH'), findsOneWidget);
    expect(find.text(l10n.sshProfile.sEmpty), findsNothing);
  });

  testWidgets('Android with termux home shows child without connection', (
    tester,
  ) async {
    final mode = ConnectionModeService(
      defaultTargetResolver: RuntimeTarget.termux,
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );
    await tester.pumpWidget(
      await _gateHost(
        mode: mode,
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsOneWidget);
    expect(find.byType(WorkEnvironmentChooserPage), findsNothing);
  });

  testWidgets('Android with ssh home and profiles shows child', (tester) async {
    await profileCubit.close();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );

    final mode = ConnectionModeService(
      defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );
    await tester.pumpWidget(
      await _gateHost(
        mode: mode,
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsOneWidget);
    expect(find.byType(WorkEnvironmentChooserPage), findsNothing);
  });

  testWidgets('unreachable home gate shows connection page with status card', (
    tester,
  ) async {
    await profileCubit.close();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );
    final homeCubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      host: 'example.com',
      port: 2222,
    );
    addTearDown(homeCubit.close);
    homeCubit.markInitial(
      const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
    );

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => profileCubit.state.hasProfiles,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.byType(RemoteConnectionsPage), findsOneWidget);
    expect(
      find.text(
        l10n.home.connectionUnreachable(host: 'example.com', port: 2222),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.home.connectionRetryNow), findsOneWidget);
  });

  testWidgets('connecting home with empty catalog shows progress, not list', (
    tester,
  ) async {
    // Regression: with an empty profile catalog `requiresSshProfileSetup` is
    // true; while the home is `connecting` the gate must show progress, not
    // fall through to the target list (that looked like "retry opens targets").
    final pending = Completer<HomeConnectResult>();
    final homeCubit = HomeConnectionCubit(
      connect: () => pending.future,
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
      host: 'example.com',
      port: 22,
    );
    addTearDown(homeCubit.close);
    unawaited(homeCubit.connectOnce());

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => false,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pump();

    expect(homeCubit.state.status, HomeConnectionStatus.connecting);
    expect(find.text(l10n.sshProfile.statusConnecting), findsOneWidget);
    expect(find.text(l10n.sshProfile.sEmpty), findsNothing);
  });

  testWidgets('unrebindable home keeps the connection page with an error', (
    tester,
  ) async {
    await profileCubit.close();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );
    final homeCubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.unknown),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      profileId: 'p1',
      host: 'example.com',
      port: 22,
    );
    addTearDown(homeCubit.close);
    homeCubit.markUnreachable(HomeErrorKind.hostIdentityChanged);

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => profileCubit.state.hasProfiles,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pumpAndSettle();

    // A recovered-but-unrebindable SSH home must never expose `child` (the
    // local fallback plane); it stays on the connection page with an
    // actionable error that names the host-identity problem.
    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.byType(RemoteConnectionsPage), findsOneWidget);
    expect(find.text(l10n.home.connectionErrorHostKey), findsOneWidget);
  });

  testWidgets('connected home gate shows child without status card', (
    tester,
  ) async {
    await profileCubit.close();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );
    final homeCubit = HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.unknown),
      cancelRetry: () async {},
      resumeRetry: () async {},
      onConnected: () {},
      host: 'example.com',
      port: 22,
    );
    addTearDown(homeCubit.close);
    homeCubit.markReconnected();

    await tester.pumpWidget(
      await _gateHost(
        mode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => profileCubit.state.hasProfiles,
        ),
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        sessionPrefs: sessionPrefs,
        termuxCubit: termuxCubit,
        homeConnectionCubit: homeCubit,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APP_CHILD'), findsOneWidget);
    expect(find.text(l10n.home.connectionRetryNow), findsNothing);
  });
}
