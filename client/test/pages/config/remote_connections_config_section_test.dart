import '../../support/ssh_connectivity_test_harness.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/config/remote_connections_config_section.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profiles_section.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/in_memory_filesystem.dart';

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _input.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _input.close();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
    unawaited(_input.close());
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

/// Records `connect` so the home-binding test can prove the remote-connections
/// surface never opens an [SshConnectionCubit] connection.
class _RecordingSshConnectionCubit extends SshConnectionCubit {
  _RecordingSshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
  }) : super(
          factory: factory,
          coordinator: coordinator,
          connectivity: TestSshConnectivity(),
        );

  final connectCalls = <String>[];

  @override
  Future<void> connect(String profileId, {bool switchHome = true}) async {
    connectCalls.add(profileId);
  }
}

/// Records the pure home-binding `select('ssh:<id>')` call. The remote
/// connection's home switch is the only effect under test here.
class _RecordingHomeTargetController implements HomeTargetController {
  final selected = <String>[];

  @override
  RuntimeTarget get current => RuntimeTarget.local();

  @override
  String get currentId => current.id;

  @override
  Future<List<RuntimeTarget>> listSelectable({String wslDistro = ''}) async =>
      [current];

  @override
  Future<List<RuntimeTarget>> listWorkspaceTargets({
    String wslDistro = '',
  }) =>
      listSelectable(wslDistro: wslDistro);

  @override
  Future<void> select(String id) async => selected.add(id);
}

void main() {
  late Directory tempDir;
  late SshProfileRepository profileRepository;
  late InMemorySshCredentialStore credentialStore;
  late InMemorySshKnownHostRepository knownHosts;
  late SshClientFactory factory;
  late SshProfileConnectionCoordinator coordinator;
  late _RecordingSshConnectionCubit connectionCubit;
  late _RecordingHomeTargetController homeTargetController;
  late SshProfileCubit profileCubit;
  late TerminalTransportFactory transportFactory;
  late AppLocalizations l10n;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remote_conn_config_');
    credentialStore = InMemorySshCredentialStore();
    knownHosts = InMemorySshKnownHostRepository();
    final events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: credentialStore,
      knownHostRepository: knownHosts,
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async =>
          _InstantAuthClient(),
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      fs: InMemoryFilesystem(),
      storage: fakeHomeStorage(),
    );
    connectionCubit = _RecordingSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
    homeTargetController = _RecordingHomeTargetController();
    profileCubit = SshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: credentialStore,
    );
    transportFactory = TerminalTransportFactory(
      sshProfileRepository: profileRepository,
      sshCredentialStore: credentialStore,
      sshKnownHostRepository: knownHosts,
      sshClientFactory: factory,
    );
    l10n = await const AppLocalizationsCompatDelegate().load(
      const Locale('en'),
    );
  });

  tearDown(() async {
    await connectionCubit.close();
    await profileCubit.close();
    await coordinator.dispose();
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpSection(WidgetTester tester) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
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
              RepositoryProvider<SshCredentialStore>.value(
                value: credentialStore,
              ),
              RepositoryProvider<TerminalTransportFactory>.value(
                value: transportFactory,
              ),
              RepositoryProvider<SshProfileRepository>.value(
                value: profileRepository,
              ),
              RepositoryProvider<HomeTargetController>.value(
                value: homeTargetController,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<SshProfileCubit>.value(value: profileCubit),
                BlocProvider<SshConnectionCubit>.value(value: connectionCubit),
              ],
              child: const Scaffold(body: RemoteConnectionsConfigSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the heading and the device-local target list', (
    tester,
  ) async {
    await pumpSection(tester);

    expect(find.text(l10n.remote.connectionsTitle), findsOneWidget);
    // The catalog is device-local and always present, independent of any
    // remote connection state — this is the always-reachable config surface.
    expect(find.byType(SshProfilesSection), findsOneWidget);
    expect(find.text(l10n.sshProfile.sTargetsTitle), findsOneWidget);
  });

  testWidgets('renders A-source profiles injected from the watched cubit', (
    tester,
  ) async {
    // The section is now presentational: RemoteConnectionsConfigSection feeds
    // it the device-local (A-source) cubit's profiles. A profile saved to the
    // device repository must flow through to the rendered list.
    await profileRepository.save(
      const SshProfile(
        id: 'a1',
        name: 'alpha-host',
        host: 'a.example.com',
        username: 'alice',
      ),
    );
    await profileCubit.load();

    await pumpSection(tester);

    expect(find.byType(SshProfilesSection), findsOneWidget);
    expect(find.text('alpha-host'), findsOneWidget);
  });

  testWidgets(
    'connect binds the SSH home instead of SshConnectionCubit.connect',
    (tester) async {
      // Remote connections is the A-source home-binding surface: tapping
      // Connect must select the home target + persist the selected profile,
      // and must NOT open an SshConnectionCubit connection (which would feed
      // the B-only status bar with an A-source host).
      await profileRepository.save(
        const SshProfile(
          id: 'a1',
          name: 'alpha-host',
          host: 'a.example.com',
          username: 'alice',
        ),
      );
      await profileCubit.load();

      await pumpSection(tester);

      await tester.tap(find.text(l10n.sshProfile.connect));
      await tester.pumpAndSettle();

      expect(connectionCubit.connectCalls, isEmpty);
      expect(homeTargetController.selected, ['ssh:a1']);
      expect(profileCubit.state.selectedProfileId, 'a1');
    },
  );
}
