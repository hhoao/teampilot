import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profile_connection_status.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profile_target_card.dart';
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
import 'package:teampilot/utils/ui/app_keys.dart';

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

  final connectCalls = <String>[];
  final disconnectCalls = <String>[];

  void seed(SshConnectionState next) => emit(next);

  @override
  Future<void> connect(String profileId) async {
    connectCalls.add(profileId);
  }

  @override
  Future<void> disconnect(String profileId) async {
    disconnectCalls.add(profileId);
  }
}

class _SeededSshProfileCubit extends SshProfileCubit {
  _SeededSshProfileCubit({
    required super.profileRepository,
    required super.credentialStore,
    required List<SshProfile> profiles,
  }) {
    emit(
      SshProfileState(profiles: profiles, selectedProfileId: profiles.first.id),
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

SshConnectionState _stateWithHost({
  required SshHostUiStatus status,
  String? errorDetail,
}) {
  return SshConnectionState(
    hostsById: {
      _profile.id: SshHostConnectionVm(
        profileId: _profile.id,
        label: _profile.name,
        host: _profile.host,
        status: status,
        errorDetail: errorDetail,
      ),
    },
    profileOrder: [_profile.id],
  );
}

Future<Widget> _host({
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required TerminalTransportFactory transportFactory,
  required SshProfileRepository profileRepository,
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
          ],
          child: const Scaffold(
            body: SingleChildScrollView(child: SshProfilesSection()),
          ),
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
  late _SeededSshProfileCubit profileCubit;
  late TerminalTransportFactory transportFactory;
  late AppLocalizations l10n;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ssh_profiles_section_');
    profileRepository = SshProfileRepository(rootDir: tempDir.path);
    await profileRepository.save(_profile);

    harness = _Harness();
    connectionCubit = harness.createConnectionCubit();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );
    transportFactory = TerminalTransportFactory(
      sshProfileRepository: profileRepository,
      sshCredentialStore: harness.credentialStore,
      sshKnownHostRepository: harness.knownHosts,
      sshClientFactory: harness.factory,
    );
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await connectionCubit.close();
    await profileCubit.close();
    await harness.dispose();
    await tempDir.delete(recursive: true);
  });

  testWidgets('Android shows Scan QR as the primary SSH action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    expect(find.byKey(AppKeys.connectScanQr), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('card status comes from SshConnectionCubit', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.connected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    expect(find.text(l10n.sshProfileStatusConnected), findsOneWidget);
    expect(find.text(l10n.sshProfileDisconnect), findsOneWidget);
  });

  testWidgets('Connect calls SshConnectionCubit.connect', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfileConnect));
    await tester.pump();

    expect(connectionCubit.connectCalls, [_profile.id]);
  });

  testWidgets('Disconnect calls SshConnectionCubit.disconnect', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.connected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfileDisconnect));
    await tester.pump();

    expect(connectionCubit.disconnectCalls, [_profile.id]);
  });

  testWidgets('card layout does not overflow at narrow width', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: SshProfileTargetCard(
                profile: _profile,
                status: SshProfileConnectionStatus.disconnected,
                testing: false,
                busy: false,
                onTest: () {},
                onConnect: () {},
                onDisconnect: () {},
                onEdit: () {},
                onDelete: () {},
                onRefresh: () {},
                onConfigure: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text(l10n.sshProfileConnect), findsNothing);
  });

  testWidgets('Test does not mark Cubit connected', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfileTest));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(connectionCubit.connectCalls, isEmpty);
    expect(
      connectionCubit.state.hostsById[_profile.id]!.status,
      SshHostUiStatus.disconnected,
    );
    expect(find.text(l10n.sshProfileStatusConnected), findsNothing);
    expect(find.text(l10n.sshProfileStatusDisconnected), findsOneWidget);
  });
}
