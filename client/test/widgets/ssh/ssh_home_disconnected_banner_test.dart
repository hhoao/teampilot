import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/widgets/ssh/ssh_home_disconnected_banner.dart';

import '../../support/in_memory_filesystem.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

Widget _host({
  required RuntimeTarget home,
  required SshConnectionCubit sshCubit,
  required Widget child,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  final mode = ConnectionModeService(
    defaultTargetResolver: () => home,
    hasSshProfiles: () => true,
  );
  final homeController = _homeTargetController(home);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: ThemeData(colorScheme: scheme),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConnectionModeService>.value(value: mode),
          RepositoryProvider<HomeTargetController>.value(value: homeController),
        ],
        child: BlocProvider<SshConnectionCubit>.value(
          value: sshCubit,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

HomeTargetController _homeTargetController(RuntimeTarget home) {
  const root = '/tp-test-ssh-banner';
  final fs = InMemoryFilesystem();
  final sshProfileRepo = SshProfileRepository(rootDir: root, fs: fs);
  final registry = RuntimeTargetRegistry(
    repo: TargetsRepository(rootDir: root, fs: fs),
    sshProfileRepo: sshProfileRepo,
    isWindows: false,
    isAndroid: false,
  );
  return HomeTargetController(
    registry: registry,
    current: () => home,
    switchTo: (_) async {},
  );
}

class _Harness {
  _Harness({
    SshClientConnector? connector,
  })  : events = SshConnectionEvents(),
        _profiles = {_profile.id: _profile} {
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: connector ??
          (profile, {timeout = const Duration(seconds: 10)}) async {
            return _InstantAuthClient();
          },
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (id) => _profiles[id],
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
  }

  final SshConnectionEvents events;
  final Map<String, SshProfile> _profiles;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;

  SshConnectionCubit createCubit() {
    return SshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
  }

  Future<void> dispose() => coordinator.dispose();
}

void main() {
  testWidgets('shows when SSH home is disconnected', (tester) async {
    final harness = _Harness();
    final cubit = harness.createCubit();
    addTearDown(() async {
      await cubit.close();
      await harness.dispose();
    });
    await cubit.syncProfiles(const [_profile]);

    await tester.pumpWidget(
      _host(
        home: RuntimeTarget.ssh(_profile.id, label: _profile.name),
        sshCubit: cubit,
        child: const SshHomeDisconnectedBanner(),
      ),
    );

    expect(
      find.text(
        'Remote SSH work home is disconnected. Shell, Git, and agent sessions '
        'are paused until you reconnect.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reconnect'), findsOneWidget);
  });

  testWidgets('reconnect calls connect', (tester) async {
    final gate = Completer<void>();
    final harness = _Harness(
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        await gate.future;
        return _InstantAuthClient();
      },
    );
    final cubit = harness.createCubit();
    addTearDown(() async {
      await cubit.close();
      await harness.dispose();
    });
    await cubit.syncProfiles(const [_profile]);

    await tester.pumpWidget(
      _host(
        home: RuntimeTarget.ssh(_profile.id, label: _profile.name),
        sshCubit: cubit,
        child: const SshHomeDisconnectedBanner(),
      ),
    );

    await tester.tap(find.text('Reconnect'));
    await tester.pump();

    expect(
      cubit.state.hostsById[_profile.id]!.status,
      SshHostUiStatus.connecting,
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(
      cubit.state.hostsById[_profile.id]!.status,
      SshHostUiStatus.connected,
    );
  });

  testWidgets('hidden when SSH home is connected', (tester) async {
    final harness = _Harness();
    final cubit = harness.createCubit();
    addTearDown(() async {
      await cubit.close();
      await harness.dispose();
    });
    await cubit.syncProfiles(const [_profile]);
    await cubit.connect(_profile.id);

    await tester.pumpWidget(
      _host(
        home: RuntimeTarget.ssh(_profile.id, label: _profile.name),
        sshCubit: cubit,
        child: const SshHomeDisconnectedBanner(),
      ),
    );

    expect(find.text('Reconnect'), findsNothing);
    expect(
      find.textContaining('Remote SSH work home is disconnected'),
      findsNothing,
    );
  });

  testWidgets('hidden when not SSH home', (tester) async {
    final harness = _Harness();
    final cubit = harness.createCubit();
    addTearDown(() async {
      await cubit.close();
      await harness.dispose();
    });
    await cubit.syncProfiles(const [_profile]);

    await tester.pumpWidget(
      _host(
        home: RuntimeTarget.local(),
        sshCubit: cubit,
        child: const SshHomeDisconnectedBanner(),
      ),
    );

    expect(find.text('Reconnect'), findsNothing);
    expect(
      find.textContaining('Remote SSH work home is disconnected'),
      findsNothing,
    );
  });
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
  Future<void> get done async {}
}
