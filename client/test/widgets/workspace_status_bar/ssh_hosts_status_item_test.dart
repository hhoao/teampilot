import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/widgets/workspace_status_bar/ssh_hosts_status_item.dart';
import 'package:teampilot/widgets/workspace_status_bar/workspace_status_bar.dart';

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

class _Harness {
  _Harness() {
    events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
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
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;

  _ControllableSshConnectionCubit createCubit() {
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

Widget _host({
  required SshConnectionCubit cubit,
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: BlocProvider<SshConnectionCubit>.value(
      value: cubit,
      child: Scaffold(body: child),
    ),
  );
}

SshConnectionState _stateWithHosts({
  required List<SshHostConnectionVm> hosts,
}) {
  final order = hosts.map((h) => h.profileId).toList(growable: false);
  return SshConnectionState(
    hostsById: {for (final h in hosts) h.profileId: h},
    profileOrder: order,
  );
}

void main() {
  testWidgets('isEmpty → no ssh-hosts-pill', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    cubit.seed(const SshConnectionState());

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [SshHostsStatusItem()],
        ),
      ),
    );

    expect(find.byKey(const Key('ssh-hosts-pill')), findsNothing);
  });

  testWidgets('with hosts → shows connected count label', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    cubit.seed(
      _stateWithHosts(
        hosts: const [
          SshHostConnectionVm(
            profileId: 'p1',
            label: 'dev',
            host: 'example.com',
            status: SshHostUiStatus.connected,
          ),
          SshHostConnectionVm(
            profileId: 'p2',
            label: 'staging',
            host: 'staging.example.com',
            status: SshHostUiStatus.disconnected,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [SshHostsStatusItem()],
        ),
      ),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.byKey(const Key('ssh-hosts-pill')), findsOneWidget);
    expect(find.text(l10n.sshHostsPillCount(1)), findsOneWidget);
  });

  testWidgets('tap Connect on inactive row → Cubit.connect called', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    cubit.seed(
      _stateWithHosts(
        hosts: const [
          SshHostConnectionVm(
            profileId: 'p-inactive',
            label: 'dev',
            host: 'example.com',
            status: SshHostUiStatus.disconnected,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [SshHostsStatusItem()],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ssh-hosts-pill')));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.sshProfileConnect));
    await tester.pump();

    expect(cubit.connectCalls, ['p-inactive']);
  });

  testWidgets('tap Manage → onManage callback invoked', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    cubit.seed(
      _stateWithHosts(
        hosts: const [
          SshHostConnectionVm(
            profileId: 'p1',
            label: 'dev',
            host: 'example.com',
            status: SshHostUiStatus.disconnected,
          ),
        ],
      ),
    );

    var managed = 0;
    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [
            SshHostsStatusItem(onManage: () => managed++),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ssh-hosts-pill')));
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(l10n.sshHostsManage));
    await tester.pump();

    expect(managed, 1);
  });
}
