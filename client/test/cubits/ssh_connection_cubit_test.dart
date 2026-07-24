import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/remote/remote_connection_monitor.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';

void main() {
  group('SshConnectionCubit', () {
    test('empty profiles → isEmpty', () {
      final harness = _Harness();
      final cubit = harness.createCubit();
      cubit.syncProfiles(const []);

      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.overallStatus, SshHostsOverallStatus.disconnected);
      expect(cubit.state.connectedCount, 0);

      cubit.close();
      harness.dispose();
    });

    test('seed: pool already live → connected', () async {
      final harness = _Harness();
      const profile = _p1;
      await harness.factory.clientForStorage(profile);

      final cubit = harness.createCubit();
      cubit.syncProfiles(const [profile]);

      expect(cubit.state.isEmpty, isFalse);
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.connected,
      );
      expect(cubit.state.overallStatus, SshHostsOverallStatus.connected);
      expect(cubit.state.connectedCount, 1);

      // Monitor.initial alone must not imply connected when pool is cold.
      await cubit.disconnect(profile.id);
      expect(harness.factory.hasLiveStorageClient(profile.id), isFalse);
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.disconnected,
      );

      await cubit.close();
      harness.dispose();
    });

    test(
      'connect → connecting then connected; selectProfileOnConnect when provided',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          connector: (profile, {timeout = const Duration(seconds: 10)}) async {
            await gate.future;
            return _InstantAuthClient();
          },
        );
        const profile = _p1;
        final selected = <String>[];
        final cubit = harness.createCubit(
          selectProfileOnConnect: (id) async => selected.add(id),
        );
        cubit.syncProfiles(const [profile]);

        final statuses = <SshHostUiStatus>[];
        final sub = cubit.stream.listen((state) {
          final host = state.hostsById[profile.id];
          if (host != null) statuses.add(host.status);
        });

        final connectFuture = cubit.connect(profile.id);
        await Future<void>.delayed(Duration.zero);
        expect(
          cubit.state.hostsById[profile.id]!.status,
          SshHostUiStatus.connecting,
        );

        gate.complete();
        await connectFuture;
        await Future<void>.delayed(Duration.zero);

        expect(
          cubit.state.hostsById[profile.id]!.status,
          SshHostUiStatus.connected,
        );
        expect(statuses, contains(SshHostUiStatus.connecting));
        expect(statuses.last, SshHostUiStatus.connected);
        expect(selected, [profile.id]);

        await sub.cancel();
        await cubit.close();
        harness.dispose();
      },
    );

    test('disconnect → disconnected + coordinator.userDisconnect', () async {
      final harness = _Harness();
      const profile = _p1;
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [profile]);

      await cubit.connect(profile.id);
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.connected,
      );

      await cubit.disconnect(profile.id);

      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.disconnected,
      );
      expect(harness.factory.hasLiveStorageClient(profile.id), isFalse);
      expect(harness.coordinator.isUserDisconnectLatched(profile.id), isTrue);

      await cubit.close();
      harness.dispose();
    });

    test(
      'overall: connecting beats partial; reconnecting host → overall connecting',
      () async {
        final gate = Completer<void>();
        var connectCalls = 0;
        final harness = _Harness(
          connector: (profile, {timeout = const Duration(seconds: 10)}) async {
            connectCalls += 1;
            if (profile.id == _p2.id) {
              await gate.future;
            }
            return _InstantAuthClient();
          },
        );
        final cubit = harness.createCubit();
        cubit.syncProfiles(const [_p1, _p2]);

        await cubit.connect(_p1.id);
        expect(cubit.state.overallStatus, SshHostsOverallStatus.partial);

        final connectP2 = cubit.connect(_p2.id);
        await Future<void>.delayed(Duration.zero);
        expect(
          cubit.state.hostsById[_p2.id]!.status,
          SshHostUiStatus.connecting,
        );
        expect(cubit.state.overallStatus, SshHostsOverallStatus.connecting);

        gate.complete();
        await connectP2;
        expect(cubit.state.overallStatus, SshHostsOverallStatus.connected);

        harness.coordinator.monitorFor(_p2.id).reconnectStarted();
        await Future<void>.delayed(Duration.zero);
        expect(
          cubit.state.hostsById[_p2.id]!.status,
          SshHostUiStatus.reconnecting,
        );
        expect(cubit.state.overallStatus, SshHostsOverallStatus.connecting);
        expect(connectCalls, greaterThanOrEqualTo(2));

        await cubit.close();
        harness.dispose();
      },
    );

    test('observation: pool change after disconnect → connected again', () async {
      final harness = _Harness();
      const profile = _p1;
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [profile]);

      await cubit.connect(profile.id);
      await cubit.disconnect(profile.id);
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.disconnected,
      );

      await harness.factory.clientForStorage(profile);
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.connected,
      );

      await cubit.close();
      harness.dispose();
    });

    test('monitor reconnecting → UI reconnecting', () async {
      final harness = _Harness();
      const profile = _p1;
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [profile]);

      await cubit.connect(profile.id);
      harness.coordinator.monitorFor(profile.id).reconnectStarted();
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.reconnecting,
      );

      await cubit.close();
      harness.dispose();
    });

    test('profile deleted → pruned; last deleted → empty', () async {
      final harness = _Harness();
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [_p1, _p2]);

      await cubit.connect(_p1.id);
      expect(cubit.state.hostsById.keys, {_p1.id, _p2.id});

      cubit.syncProfiles(const [_p2]);
      expect(cubit.state.hostsById.keys, {_p2.id});
      expect(cubit.state.isEmpty, isFalse);

      cubit.syncProfiles(const []);
      expect(cubit.state.isEmpty, isTrue);
      expect(cubit.state.hostsById, isEmpty);

      await cubit.close();
      harness.dispose();
    });

    test('connect failure → error / authFailed', () async {
      final harness = _Harness(
        connector: (profile, {timeout = const Duration(seconds: 10)}) async {
          if (profile.id == _p1.id) {
            throw SSHAuthFailError('bad password');
          }
          throw StateError('transport boom');
        },
      );
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [_p1, _p2]);

      await cubit.connect(_p1.id);
      expect(
        cubit.state.hostsById[_p1.id]!.status,
        SshHostUiStatus.authFailed,
      );
      expect(cubit.state.hostsById[_p1.id]!.errorDetail, isNotNull);

      await cubit.connect(_p2.id);
      expect(cubit.state.hostsById[_p2.id]!.status, SshHostUiStatus.error);
      expect(cubit.state.hostsById[_p2.id]!.errorDetail, isNotNull);

      await cubit.close();
      harness.dispose();
    });

    test('hostkey failure → authFailed', () async {
      final harness = _Harness(
        connector: (profile, {timeout = const Duration(seconds: 10)}) async {
          throw SSHAuthAbortError(
            'aborted',
            SSHHostkeyError('Hostkey verification failed'),
          );
        },
      );
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [_p1]);

      await cubit.connect(_p1.id);
      expect(
        cubit.state.hostsById[_p1.id]!.status,
        SshHostUiStatus.authFailed,
      );

      await cubit.close();
      harness.dispose();
    });

    test('monitor degraded → UI still connected', () async {
      final harness = _Harness();
      const profile = _p1;
      final cubit = harness.createCubit();
      cubit.syncProfiles(const [profile]);

      await cubit.connect(profile.id);
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.connected,
      );

      harness.coordinator.monitorFor(profile.id).heartbeatTimedOut();
      await Future<void>.delayed(Duration.zero);

      expect(
        harness.coordinator.monitorFor(profile.id).state.status,
        RemoteConnectionStatus.degraded,
      );
      expect(
        cubit.state.hostsById[profile.id]!.status,
        SshHostUiStatus.connected,
      );

      await cubit.close();
      harness.dispose();
    });

    test('inactiveHosts sorts by label; connectedHosts filters connected', () async {
      final harness = _Harness();
      final cubit = harness.createCubit();
      const zebra = SshProfile(
        id: 'z',
        name: 'Zebra',
        host: 'z.example.com',
        username: 'u',
      );
      const alpha = SshProfile(
        id: 'a',
        name: 'Alpha',
        host: 'a.example.com',
        username: 'u',
      );
      cubit.syncProfiles(const [zebra, alpha]);

      await cubit.connect(alpha.id);

      expect(
        cubit.state.connectedHosts.map((h) => h.profileId),
        [alpha.id],
      );
      expect(
        cubit.state.inactiveHosts.map((h) => h.label),
        ['Zebra'],
      );

      // Both inactive → sorted by label
      await cubit.disconnect(alpha.id);
      expect(
        cubit.state.inactiveHosts.map((h) => h.label),
        ['Alpha', 'Zebra'],
      );

      await cubit.close();
      harness.dispose();
    });
  });
}

const _p1 = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

const _p2 = SshProfile(
  id: 'p2',
  name: 'staging',
  host: 'staging.example.com',
  username: 'bob',
);

class _Harness {
  _Harness({SshClientConnector? connector})
    : events = SshConnectionEvents(),
      _profiles = {_p1.id: _p1, _p2.id: _p2} {
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector:
          connector ??
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

  SshConnectionCubit createCubit({
    Future<void> Function(String id)? selectProfileOnConnect,
  }) {
    return SshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
      selectProfileOnConnect: selectProfileOnConnect,
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
  Future<void> get done async {}
}
