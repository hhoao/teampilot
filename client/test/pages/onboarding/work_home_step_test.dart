import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/cubits/termux_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/onboarding/steps/work_home_step.dart';
import 'package:teampilot/pages/ssh_profiles_page.dart';
import 'package:teampilot/pages/termux/termux_setup_page.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class SpyTermuxCubit extends TermuxCubit {
  SpyTermuxCubit({
    required super.store,
    required super.credentials,
    required super.nativeAppDataPath,
    required super.selectHome,
    required super.testConnect,
    this.onConnect,
    this.fastSaveConfig = false,
  });

  final Future<void> Function()? onConnect;
  final bool fastSaveConfig;

  int connectCalls = 0;

  @override
  Future<void> saveConfig(TermuxConfig config) async {
    if (fastSaveConfig) {
      emit(state.copyWith(config: config, clearLastError: true));
      return;
    }
    await super.saveConfig(config);
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    if (onConnect != null) {
      await onConnect!();
      return;
    }
    await super.connect();
  }
}

class _ControllableSshConnectionCubit extends SshConnectionCubit {
  _ControllableSshConnectionCubit({
    required super.factory,
    required super.coordinator,
  });

  @override
  Future<void> connect(String profileId) async {}

  @override
  Future<void> disconnect(String profileId) async {}
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

void _largeTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 10000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, -1200));
  await tester.pump();
}

SpyTermuxCubit _createSpyCubit(Directory nativeDir, {bool fastSaveConfig = false}) {
  final store = TermuxConfigStore(
    rootDir: nativeDir.path,
    fs: LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(nativeDir.path),
    ),
  );
  late SpyTermuxCubit spy;
  spy = SpyTermuxCubit(
    store: store,
    credentials: InMemorySshCredentialStore(),
    nativeAppDataPath: nativeDir.path,
    fastSaveConfig: fastSaveConfig,
    selectHome: (_) async {},
    testConnect: (_) async => (ok: true, message: ''),
    onConnect: () async {
      spy.emit(
        spy.state.copyWith(
          connected: true,
          connecting: false,
          clearLastError: true,
        ),
      );
    },
  );
  return spy;
}

Future<void> _pumpWorkHomeStep(
  WidgetTester tester, {
  required VoidCallback onBound,
  required ConnectionModeService mode,
  required SessionPreferencesCubit sessionPrefs,
  required SpyTermuxCubit termuxCubit,
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required SshProfileRepository profileRepository,
  required TerminalTransportFactory transportFactory,
}) async {
  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    MaterialApp(
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
            RepositoryProvider<ConnectionModeService>.value(value: mode),
            RepositoryProvider<SshCredentialStore>.value(value: credentialStore),
            RepositoryProvider<TerminalTransportFactory>.value(
              value: transportFactory,
            ),
            RepositoryProvider<SshProfileRepository>.value(
              value: profileRepository,
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SshProfileCubit>.value(value: profileCubit),
              BlocProvider<SshConnectionCubit>.value(value: connectionCubit),
              BlocProvider<SessionPreferencesCubit>.value(value: sessionPrefs),
              BlocProvider<TermuxCubit>.value(value: termuxCubit),
            ],
            child: Scaffold(
              body: SizedBox(
                height: 520,
                child: OnboardingWorkHomeStep(onBound: onBound),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
}

void main() {
  late Directory nativeDir;
  late Directory tempDir;
  late _Harness harness;
  late SpyTermuxCubit termuxCubit;
  late SessionPreferencesCubit sessionPrefs;
  late SshProfileRepository profileRepository;
  late SshProfileCubit profileCubit;
  late SshConnectionCubit connectionCubit;
  late TerminalTransportFactory transportFactory;
  late RuntimeTarget Function() homeResolver;
  late ConnectionModeService mode;

  setUp(() async {
    setUpTestAppStorage();
    SharedPreferences.setMockInitialValues({});
    nativeDir = await Directory.systemTemp.createTemp('work_home_termux_');
    tempDir = await Directory.systemTemp.createTemp('work_home_ssh_');
    AppPathsBootstrapper.syncPaths(AppPaths(nativeDir.path));

    harness = _Harness();
    connectionCubit = harness.createConnectionCubit();
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      fs: InMemoryFilesystem(),
    );
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

    homeResolver = RuntimeTarget.local;
    mode = ConnectionModeService(
      defaultTargetResolver: () => homeResolver(),
      hasSshProfiles: () => profileCubit.state.hasProfiles,
    );

    termuxCubit = _createSpyCubit(nativeDir, fastSaveConfig: true);
  });

  tearDown(() async {
    tearDownTestAppStorage();
    await connectionCubit.close();
    await profileCubit.close();
    if (!termuxCubit.isClosed) await termuxCubit.close();
    await sessionPrefs.close();
    await harness.dispose();
    if (await nativeDir.exists()) {
      await nativeDir.delete(recursive: true);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void setHome(RuntimeTarget target) {
    homeResolver = () => target;
  }

  testWidgets('Termux onHomeBound notifies parent', (tester) async {
    _largeTestSurface(tester);
    var boundCalls = 0;

    await _pumpWorkHomeStep(
      tester,
      onBound: () => boundCalls++,
      mode: mode,
      sessionPrefs: sessionPrefs,
      termuxCubit: termuxCubit,
      profileCubit: profileCubit,
      connectionCubit: connectionCubit,
      credentialStore: harness.credentialStore,
      profileRepository: profileRepository,
      transportFactory: transportFactory,
    );

    await tester.tap(find.text('On-device · Termux'));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }

    expect(find.byType(TermuxSetupPage), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('termux_username_field')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('termux_username_field')),
      'u0_a123',
    );
    await tester.pump();
    await _scrollToBottom(tester);
    final connectButton = find.byKey(const Key('termux_connect_button'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(boundCalls, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('SSH Connect notifies via SessionPreferencesCubit watch', (
    tester,
  ) async {
    _largeTestSurface(tester);
    var boundCalls = 0;

    await _pumpWorkHomeStep(
      tester,
      onBound: () => boundCalls++,
      mode: mode,
      sessionPrefs: sessionPrefs,
      termuxCubit: termuxCubit,
      profileCubit: profileCubit,
      connectionCubit: connectionCubit,
      credentialStore: harness.credentialStore,
      profileRepository: profileRepository,
      transportFactory: transportFactory,
    );

    await tester.tap(find.text('Remote · SSH'));
    await tester.pumpAndSettle();
    expect(find.byType(SshProfilesPage), findsOneWidget);
    expect(boundCalls, 0);

    // Simulate Connect home bind the same way StartupGate rebuilds: update
    // the home resolver, then emit on SessionPreferencesCubit (not watching
    // ConnectionModeService directly).
    setHome(RuntimeTarget.ssh('p1', label: 'box'));
    sessionPrefs.mergeLocatedExecutables({CliTool.claude: '/tmp/claude'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(boundCalls, 1);
  });

  testWidgets('saving SSH profile alone does not call onBound', (tester) async {
    _largeTestSurface(tester);
    var boundCalls = 0;

    await _pumpWorkHomeStep(
      tester,
      onBound: () => boundCalls++,
      mode: mode,
      sessionPrefs: sessionPrefs,
      termuxCubit: termuxCubit,
      profileCubit: profileCubit,
      connectionCubit: connectionCubit,
      credentialStore: harness.credentialStore,
      profileRepository: profileRepository,
      transportFactory: transportFactory,
    );

    await tester.tap(find.text('Remote · SSH'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SshProfilesPage));
    // ignore: unawaited_futures — completes when setup route pops
    openSshProfileEditor(ctx, useFullPageEditor: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('新增 SSH Profile'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'My Box');
    await tester.enterText(find.byType(TextFormField).at(1), 'example.com');
    await tester.enterText(find.byType(TextFormField).at(3), 'alice');
    await tester.enterText(
      find.byType(TpTextarea),
      '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----',
    );

    await tester.scrollUntilVisible(
      find.widgetWithText(ElevatedButton, '保存 Profile'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '保存 Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 40 && profileCubit.state.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(profileCubit.state.hasProfiles, isTrue);
    expect(boundCalls, 0);
  });
}
