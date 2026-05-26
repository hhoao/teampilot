import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

void main() {
  test('clientFor reuses the same pooled client for one profile', () async {
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

    final first = await factory.clientFor(profile);
    final second = await factory.clientFor(profile);

    expect(identical(first, second), isTrue);
    expect(createCount, 1);
    expect(first.isClosed, isFalse);
  });

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

    final client = await factory.clientFor(profile);
    factory.disconnectProfile('p1');

    expect(client.isClosed, isTrue);

    await factory.clientFor(profile);
    expect(createCount, 2);
  });

  test('clientFor reconnects when host identity changes', () async {
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

    final first = await factory.clientFor(profileV1);
    final second = await factory.clientFor(profileV2);

    expect(identical(first, second), isFalse);
    expect(first.isClosed, isTrue);
    expect(second.isClosed, isFalse);
    expect(createCount, 2);
  });
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
