import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

void main() {
  test(
    'clientForStorage reuses the same pooled client for one profile',
    () async {
      var createCount = 0;
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        connector: (profile, {timeout = const Duration(seconds: 10)}) async {
          createCount += 1;
          return _InstantAuthClient();
        },
      );

      const profile = SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'example.com',
        username: 'alice',
      );

      final first = await factory.clientForStorage(profile);
      final second = await factory.clientForStorage(profile);

      expect(identical(first, second), isTrue);
      expect(createCount, 1);
      expect(first.isClosed, isFalse);
    },
  );

  test('disconnectProfile closes and drops pooled client', () async {
    var createCount = 0;
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        return _InstantAuthClient();
      },
    );

    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final client = await factory.clientForStorage(profile);
    factory.disconnectProfile('p1');

    expect(client.isClosed, isTrue);

    await factory.clientForStorage(profile);
    expect(createCount, 2);
  });

  test('clientForStorage reconnects when host identity changes', () async {
    var createCount = 0;
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        return _InstantAuthClient();
      },
    );

    const profileV1 = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'one.example.com',
      username: 'alice',
    );
    const profileV2 = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'two.example.com',
      username: 'alice',
    );

    final first = await factory.clientForStorage(profileV1);
    final second = await factory.clientForStorage(profileV2);

    expect(identical(first, second), isFalse);
    expect(first.isClosed, isTrue);
    expect(second.isClosed, isFalse);
    expect(createCount, 2);
  });

  test('hasLiveStorageClient is false until clientForStorage succeeds', () async {
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );

    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    expect(factory.hasLiveStorageClient(profile.id), isFalse);
    await factory.clientForStorage(profile);
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
  });

  test('hasLiveStorageClient stays false while authentication is pending', () async {
    final authGate = Completer<void>();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _DelayedAuthClient(authGate.future);
      },
    );

    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    expect(factory.hasLiveStorageClient(profile.id), isFalse);
    final pending = factory.clientForStorage(profile);
    expect(factory.hasLiveStorageClient(profile.id), isFalse);
    authGate.complete();
    await pending;
    expect(factory.hasLiveStorageClient(profile.id), isTrue);
  });

  test('storagePoolChanges emits on open and disconnectProfile', () async {
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );

    const profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'example.com',
      username: 'alice',
    );

    final events = <String>[];
    final sub = factory.storagePoolChanges.listen(events.add);
    await factory.clientForStorage(profile);
    factory.disconnectProfile(profile.id);
    await Future<void>.delayed(Duration.zero);
    expect(events, [profile.id, profile.id]);
    await sub.cancel();
  });

  test(
    'auth failure leaves hasLiveStorageClient false and emits no open',
    () async {
      final factory = SshClientFactory(
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
        connector: (profile, {timeout = const Duration(seconds: 10)}) async {
          return _FailAuthClient();
        },
      );

      const profile = SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'example.com',
        username: 'alice',
      );

      final events = <String>[];
      final sub = factory.storagePoolChanges.listen(events.add);
      await expectLater(
        factory.clientForStorage(profile),
        throwsA(isA<StateError>()),
      );
      expect(factory.hasLiveStorageClient(profile.id), isFalse);
      expect(events, isEmpty);
      await sub.cancel();
    },
  );
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();
}

class _DelayedAuthClient extends SSHClient {
  _DelayedAuthClient(Future<void> gate)
    : _gate = gate,
      super(_FakeSSHSocket(), username: 'test');

  final Future<void> _gate;

  @override
  Future<void> get authenticated => _gate;
}

class _FailAuthClient extends SSHClient {
  _FailAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated =>
      Future<void>.error(StateError('authentication failed'));
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
