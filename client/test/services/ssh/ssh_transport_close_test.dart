import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'dev',
    host: 'example.com',
    username: 'alice',
  );

  test('disconnectProfile reports userDisconnect on storage plane', () async {
    final events = SshConnectionEvents();
    final closes = <SshTransportClosed>[];
    events.onTransportClosed = (_, error, _) {
      if (error is SshTransportClosed) closes.add(error);
    };

    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );

    await factory.clientForStorage(profile);
    factory.disconnectProfile(
      profile.id,
      reason: SshTransportCloseReason.userDisconnect,
    );
    await Future<void>.delayed(Duration.zero);

    expect(closes, hasLength(1));
    expect(closes.single.reason, SshTransportCloseReason.userDisconnect);
    expect(closes.single.plane, SshTransportPlane.storage);
  });

  test('remote storage close reports remotePeerClosed', () async {
    final events = SshConnectionEvents();
    final closes = <SshTransportClosed>[];
    events.onTransportClosed = (_, error, _) {
      if (error is SshTransportClosed) closes.add(error);
    };

    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );

    final client = await factory.clientForStorage(profile);
    client.close();
    await client.done;
    await Future<void>.delayed(Duration.zero);

    expect(closes, hasLength(1));
    expect(closes.single.reason, SshTransportCloseReason.remotePeerClosed);
    expect(closes.single.plane, SshTransportPlane.storage);
  });

  test('member client close does not evict live storage pool', () async {
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );

    final storage = await factory.clientForStorage(profile);
    final member = await factory.createMemberClient(profile);
    member.close();
    await member.done;
    await Future<void>.delayed(Duration.zero);

    expect(factory.hasLiveStorageClient(profile.id), isTrue);
    expect(storage.isClosed, isFalse);

    storage.close();
    await storage.done;
    expect(factory.hasLiveStorageClient(profile.id), isFalse);
  });

  test('coalesce keeps specific transport error over generic remote close', () async {
    final events = SshConnectionEvents();
    final disconnects = <Object>[];
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
      policy: const SshProfileReconnectPolicy(
        disconnectCoalesce: Duration(milliseconds: 20),
        maxAttempts: 0,
      ),
      onDisconnect: (_, error, _) => disconnects.add(error),
    );

    events.onTransportClosed?.call(
      profile.id,
      const SshTransportClosed(
        reason: SshTransportCloseReason.transportError,
        plane: SshTransportPlane.storage,
        cause: SocketException('Connection reset by peer'),
      ),
      StackTrace.empty,
    );
    events.onTransportClosed?.call(
      profile.id,
      const SshTransportClosed(
        reason: SshTransportCloseReason.remotePeerClosed,
        plane: SshTransportPlane.storage,
      ),
      StackTrace.empty,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(disconnects, hasLength(1));
    final closed = disconnects.single;
    expect(closed, isA<SshTransportClosed>());
    expect(
      (closed as SshTransportClosed).reason,
      SshTransportCloseReason.transportError,
    );
    expect(closed.cause, isA<SocketException>());
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
