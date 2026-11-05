import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_protocol.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_shared_client.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'test',
  host: 'example.test',
  username: 'tester',
);

const _target = SshWorkerDialTarget(host: '127.0.0.1', port: 22);

void main() {
  test(
    'shares one authenticated client across concurrent acquisitions',
    () async {
      final clients = <_FakeSshClient>[];
      final shared = SshWorkerSharedClient(
        profileId: _profile.id,
        openClient:
            ({required profile, required target, required timeout}) async {
              final client = _FakeSshClient();
              clients.add(client);
              return client;
            },
      );

      final first = await shared.acquire(
        profile: _profile,
        target: _target,
        timeout: const Duration(seconds: 1),
      );
      final second = await shared.acquire(
        profile: _profile,
        target: _target,
        timeout: const Duration(seconds: 1),
      );

      expect(identical(first, second), isTrue);
      expect(clients, hasLength(1));
      expect(
        await shared.acquire(
          profile: _profile,
          target: _target,
          timeout: const Duration(seconds: 1),
        ),
        same(first),
      );
      expect(clients, hasLength(1));

      await shared.close();
      expect(clients.single.closeCount, 1);
    },
  );

  test('routes concurrent opens through one single-flight client', () async {
    final gate = Completer<void>();
    var opens = 0;
    final shared = SshWorkerSharedClient(
      profileId: _profile.id,
      openClient:
          ({required profile, required target, required timeout}) async {
            opens++;
            await gate.future;
            return _FakeSshClient();
          },
    );

    final first = shared.acquire(
      profile: _profile,
      target: _target,
      timeout: const Duration(seconds: 1),
    );
    final second = shared.acquire(
      profile: _profile,
      target: _target,
      timeout: const Duration(seconds: 1),
    );
    gate.complete();
    final clients = await Future.wait([first, second]);

    expect(opens, 1);
    expect(identical(clients.first, clients.last), isTrue);
    await shared.close();
  });

  test('rejects a changed dial target while the client is live', () async {
    final shared = SshWorkerSharedClient(
      profileId: _profile.id,
      openClient:
          ({required profile, required target, required timeout}) async =>
              _FakeSshClient(),
    );
    await shared.acquire(
      profile: _profile,
      target: _target,
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      shared.acquire(
        profile: _profile,
        target: const SshWorkerDialTarget(host: 'other.test', port: 22),
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
    await shared.close();
  });

  test('re-dials a new target after the old client closes', () async {
    final clients = <_FakeSshClient>[];
    final shared = SshWorkerSharedClient(
      profileId: _profile.id,
      openClient:
          ({required profile, required target, required timeout}) async {
            final client = _FakeSshClient();
            clients.add(client);
            return client;
          },
    );
    final first = await shared.acquire(
      profile: _profile,
      target: _target,
      timeout: const Duration(seconds: 1),
    );
    await first.close();

    final second = await shared.acquire(
      profile: _profile,
      target: const SshWorkerDialTarget(host: 'other.test', port: 2222),
      timeout: const Duration(seconds: 1),
    );

    expect(identical(first, second), isFalse);
    expect(clients, hasLength(2));
    await shared.close();
  });
}

final class _FakeSshClient extends SSHClient {
  _FakeSshClient() : super(_FakeSocket(), username: 'tester');

  final _done = Completer<void>();
  var closeCount = 0;
  var _closed = false;

  @override
  Future<void> get authenticated async {}

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    closeCount++;
    _done.complete();
  }

  @override
  Future<void> disconnect() => close();
}

final class _FakeSocket implements SSHSocket {
  final _stream = StreamController<Uint8List>();
  final _sink = StreamController<List<int>>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _stream.stream;

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _stream.close();
    await _sink.close();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> flush() async {}
}
