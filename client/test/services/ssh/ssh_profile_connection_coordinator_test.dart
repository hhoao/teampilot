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
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();
}

class _ClosableClient extends SSHClient {
  _ClosableClient() : super(_FakeSSHSocket(), username: 'test');

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
