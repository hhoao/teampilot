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
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/ssh_profiles_page.dart';
import 'package:teampilot/pages/startup_gate.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/ssh/android_ssh_connect_home.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
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
    required super.factory,
    required super.coordinator,
  });

  @override
  Future<void> connect(String profileId) async {}

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

Future<Widget> _gateHost({
  required ConnectionModeService mode,
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required TerminalTransportFactory transportFactory,
  required SshProfileRepository profileRepository,
  required SessionPreferencesCubit sessionPrefs,
  bool? isAndroid,
  Widget child = const Text('APP_CHILD'),
}) async {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
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
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('startup_gate_');
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      fs: InMemoryFilesystem(),
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
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    await connectionCubit.close();
    await profileCubit.close();
    await sessionPrefs.close();
    await harness.dispose();
    await tempDir.delete(recursive: true);
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
    expect(find.text(l10n.sshProfilesEmpty), findsOneWidget);
  });

  testWidgets('full-page editor push/pop returns to list', (tester) async {
    await pumpGatedEmptyList(tester);

    final ctx = tester.element(find.byType(SshProfilesPage));
    // Do not await: push completes only after the route is popped.
    final editor = openSshProfileEditor(ctx, useFullPageEditor: true);
    await tester.pumpAndSettle();
    expect(find.text('新增 SSH Profile'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await editor;
    expect(find.text('新增 SSH Profile'), findsNothing);
    expect(find.text(l10n.sshProfilesEmpty), findsOneWidget);
  });

  testWidgets('save does not clear gate (still list, not APP_CHILD)', (
    tester,
  ) async {
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
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsNothing);
    expect(find.text(l10n.sshProfilesEmpty), findsOneWidget);

    // Editing skips credential validators so save can complete without filling
    // the private-key FormField / TpTextarea pair.
    final ctx = tester.element(find.byType(SshProfilesPage));
    // ignore: unawaited_futures — completes when setup route pops
    openSshProfileEditor(
      ctx,
      profile: _profile,
      useFullPageEditor: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('编辑 SSH Profile'), findsOneWidget);

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

    expect(find.text('APP_CHILD'), findsNothing);
    expect(profileCubit.state.hasProfiles, isTrue);
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
      isAndroid: true,
    );

    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsNothing);

    await applyAndroidSshConnectHome(
      profileId: 'p1',
      selectHome: (id) async => homeId = id,
      selectProfile: (_) async {},
    );

    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();
    expect(find.text('APP_CHILD'), findsOneWidget);
  });
}
