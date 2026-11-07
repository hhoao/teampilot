import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/ssh_profiles_page.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
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

  Widget host(HomeStorage storage) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(useMaterial3: true),
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<HomeStorage>.value(value: storage),
          ],
          child: BlocProvider<SshConnectionCubit>.value(
            value: connectionCubit,
            child: const SshServersPage(),
          ),
        ),
      );

  testWidgets('not-connected branch shows the not-connected message',
      (tester) async {
    // Default state has no connected hosts; no config cubit is even created.
    await tester.pumpWidget(host(fakeHomeStorage()));
    await tester.pumpAndSettle();

    expect(find.text('Not connected to a remote host.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('remote load failure shows a localized message and retry',
      (tester) async {
    connectionCubit.seed(const SshConnectionState(
      hostsById: {
        'p1': SshHostConnectionVm(
          profileId: 'p1',
          label: 'dev',
          host: 'example.com',
          status: SshHostUiStatus.connected,
        ),
      },
      profileOrder: ['p1'],
    ));

    // A dropped remote transport makes the repository rethrow from loadAll().
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
    required super.factory,
    required super.coordinator,
  });

  void seed(SshConnectionState state) => emit(state);
}

/// Filesystem whose reads fail the way a closed SSH/SFTP channel does, so
/// SshServerProfileRepository.loadAll() rethrows a transport failure.
class _TransportFailingFilesystem extends InMemoryFilesystem {
  @override
  Future<FsStat> stat(String path) async =>
      const FsStat(kind: FsEntityKind.file);

  @override
  Future<String?> readString(String path) async =>
      throw StateError('SSH client closed');
}
