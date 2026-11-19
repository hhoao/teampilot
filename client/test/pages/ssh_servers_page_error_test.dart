import '../support/ssh_connectivity_test_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/ssh_profiles_page.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  // Minimal real wiring for the SshConnectionCubit that _SshServersView reads.
  late SshClientFactory factory;
  late SshProfileConnectionCoordinator coordinator;
  late _SeededSshConnectionCubit connectionCubit;

  setUp(() {
    final events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
    );
    connectionCubit = _SeededSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
  });

  tearDown(() async {
    await connectionCubit.close();
    await coordinator.dispose();
  });

  Widget host(HomeStorage storage) {
    // Device-local connection catalog: adoption seeds it from legacy plane
    // rows, and it never rides the (possibly remote) home plane.
    final deviceFs = InMemoryFilesystem();
    final deviceStorage = fakeHomeStorage(filesystem: deviceFs);
    return MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(useMaterial3: true),
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<HomeStorage>.value(value: storage),
          RepositoryProvider<SshProfileRepository>.value(
            value: SshProfileRepository(
              connections: ConnectionStore(rootDir: '/device', fs: deviceFs),
              storage: deviceStorage,
            ),
          ),
        ],
        child: BlocProvider<SshConnectionCubit>.value(
          value: connectionCubit,
          child: const SshServersPage(),
        ),
      ),
    );
  }

  testWidgets('not-connected branch shows the not-connected message', (
    tester,
  ) async {
    // A native home plane has no remote server catalog to read.
    await tester.pumpWidget(host(fakeHomeStorage()));
    await tester.pumpAndSettle();

    expect(find.text('Not connected to a remote host.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('reads profiles stored on the remote home plane', (tester) async {
    // Profiles already present on the host are listed without any local
    // connect/push having created them.
    final fs = _RemoteFilesystem();
    fs.files['/tp/ssh_profiles/profiles.json'] =
        '[{"schemaVersion":1,"id":"p1","name":"prod-db","host":"10.0.0.5",'
        '"port":2222,"username":"alice","authType":"privateKey"}]';
    await tester.pumpWidget(host(fakeHomeStorage(filesystem: fs)));
    await tester.pumpAndSettle();

    expect(find.text('prod-db'), findsOneWidget);
    expect(find.textContaining('alice@10.0.0.5:2222'), findsOneWidget);
    expect(find.text('Not connected to a remote host.'), findsNothing);
  });

  testWidgets('a listed machine with no local connection stays visible', (
    tester,
  ) async {
    final fs = _RemoteFilesystem();
    fs.files['/tp/ssh_profiles/profiles.json'] =
        '{"schemaVersion":2,"entries":[{"machineId":"m1",'
        '"displayName":"lab-box","updatedAt":1}]}';
    await tester.pumpWidget(host(fakeHomeStorage(filesystem: fs)));
    await tester.pumpAndSettle();

    // Membership is visible even though this device has no dial plan: hiding
    // it is how a machine silently disappears from the catalog UI.
    expect(find.text('lab-box'), findsOneWidget);
    expect(
      find.text('No connection from this device yet'),
      findsOneWidget,
    );
  });

  testWidgets('remote load failure shows a localized message and retry', (
    tester,
  ) async {
    // A dropped remote transport makes the repository rethrow from loadAll().
    // The gate now follows the home plane (isRemote), not connectedHosts.
    await tester.pumpWidget(
      host(fakeHomeStorage(filesystem: _TransportFailingFilesystem())),
    );
    // Flush the async load(): isLoading -> error (no spinner left).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(
      find.text(
        'Could not load the SSH servers. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Tapping retry re-invokes load() without crashing.
    await tester.tap(find.text('Retry'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      find.text(
        'Could not load the SSH servers. Check the connection and try again.',
      ),
      findsOneWidget,
    );
  });
}

/// A connection cubit whose state can be seeded directly, avoiding a real SSH
/// dial while still exercising the real `context.watch<SshConnectionCubit>()`.
class _SeededSshConnectionCubit extends SshConnectionCubit {
  _SeededSshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
  }) : super(
        factory: factory,
        coordinator: coordinator,
        connectivity: TestSshConnectivity(),
      );

  void seed(SshConnectionState state) => emit(state);
}

/// In-memory filesystem that reports a remote (SSH) home plane.
class _RemoteFilesystem extends InMemoryFilesystem {
  @override
  bool get isRemote => true;
}

/// Filesystem whose reads fail the way a closed SSH/SFTP channel does, so
/// SshServerProfileRepository.loadAll() rethrows a transport failure. It
/// reports a remote plane so the SSH servers page takes the read branch.
class _TransportFailingFilesystem extends _RemoteFilesystem {
  @override
  Future<FsStat> stat(String path) async =>
      const FsStat(kind: FsEntityKind.file);

  @override
  Future<String?> readString(String path) async =>
      throw StateError('SSH client closed');
}
