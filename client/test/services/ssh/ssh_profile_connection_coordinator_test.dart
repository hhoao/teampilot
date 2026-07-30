import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/remote/remote_connection_monitor.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';

void main() {
  test('transport close coalesces and notifies coordinator once per wave', () async {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final notifications = <String>[];
    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _ClosableClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
      policy: const SshProfileReconnectPolicy(
        disconnectCoalesce: Duration(milliseconds: 50),
        maxAttempts: 0,
      ),
      onDisconnect: (profileId, error, _) => notifications.add(profileId),
    );

    final first = await factory.clientForStorage(profile);
    final second = await factory.createMemberClient(profile);
    first.close();
    second.close();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(notifications, ['p1']);
    expect(
      coordinator.monitorFor('p1').state.status,
      RemoteConnectionStatus.down,
    );

    await factory.clientForStorage(profile);
    expect(notifications.length, 1);
    await coordinator.dispose();
  });

  test('reconnectStorage serializes concurrent attempts', () async {
    var createCount = 0;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return _InstantAuthClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
    );

    final attempts = await Future.wait([
      coordinator.reconnectStorage(profile),
      coordinator.reconnectStorage(profile),
    ]);

    expect(attempts.length, 2);
    expect(createCount, 1);
    expect(
      coordinator.monitorFor('p1').state.status,
      RemoteConnectionStatus.connected,
    );
    await coordinator.dispose();
  });

  test('hostkey verification failures do not schedule reconnect', () async {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    var createCount = 0;
    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        return _ClosableClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
      policy: const SshProfileReconnectPolicy(
        disconnectCoalesce: Duration(milliseconds: 20),
        maxAttempts: 3,
      ),
    );

    final client = await factory.clientForStorage(profile);
    events.onTransportClosed?.call(
      profile.id,
      SSHHostkeyError('Hostkey verification failed'),
      StackTrace.current,
    );
    client.close();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(createCount, 1);
    await coordinator.dispose();
  });

  test('userDisconnect sets latch and skips auto-reconnect after transport close', () async {
    var createCount = 0;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        return _ClosableClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
      policy: const SshProfileReconnectPolicy(
        disconnectCoalesce: Duration(milliseconds: 20),
        initialDelay: Duration(milliseconds: 30),
        maxAttempts: 3,
      ),
    );

    await coordinator.userConnect(profile);
    expect(createCount, 1);

    await coordinator.userDisconnect(profile.id);
    expect(coordinator.isUserDisconnectLatched(profile.id), isTrue);

    events.onTransportClosed?.call(
      profile.id,
      const SshTransportClosed(
        reason: SshTransportCloseReason.remotePeerClosed,
        plane: SshTransportPlane.storage,
      ),
      StackTrace.empty,
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(createCount, 1);
    expect(coordinator.isUserDisconnectLatched(profile.id), isTrue);
    expect(
      coordinator.monitorFor('p1').state.status,
      RemoteConnectionStatus.down,
    );
    await coordinator.dispose();
  });

  test('userConnect clears latch and opens storage pool', () async {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
    );

    await coordinator.userConnect(profile);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
    expect(coordinator.isUserDisconnectLatched(profile.id), isFalse);
    await coordinator.dispose();
  });

  test('external clientForStorage after userDisconnect clears latch via pool observation', () async {
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
    );

    await coordinator.userConnect(profile);
    await coordinator.userDisconnect(profile.id);
    expect(coordinator.isUserDisconnectLatched(profile.id), isTrue);

    await factory.clientForStorage(profile);
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.isUserDisconnectLatched(profile.id), isFalse);
    await coordinator.dispose();
  });

  test('userDisconnect aborts in-flight reconnect without leaving pool open', () async {
    var createCount = 0;
    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final sessionSignals = <String>[];
    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        if (createCount > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        return _InstantAuthClient();
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => profile,
      policy: const SshProfileReconnectPolicy(
        disconnectCoalesce: Duration(milliseconds: 10),
        initialDelay: Duration.zero,
        maxAttempts: 3,
      ),
    );
    coordinator.sessionReconnectSignals.listen(sessionSignals.add);

    await coordinator.userConnect(profile);
    final client = await factory.clientForStorage(profile);
    client.close();

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(
      coordinator.monitorFor('p1').state.status,
      RemoteConnectionStatus.reconnecting,
    );

    await coordinator.userDisconnect(profile.id);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(coordinator.isUserDisconnectLatched(profile.id), isTrue);
    expect(factory.hasLiveStorageClient(profile.id), isFalse);
    expect(sessionSignals, isEmpty);
    expect(
      coordinator.monitorFor('p1').state.status,
      RemoteConnectionStatus.down,
    );
    await coordinator.dispose();
  });
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}
}

class _ClosableClient extends SSHClient {
  _ClosableClient() : super(_FakeSSHSocket(), username: 'test');

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
