import 'dart:async';
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

import '../../support/post_frame_test_harness.dart';

const _profile = SshProfile(
  id: 'home',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

void main() {
  test('persistRetry keeps scheduling past the policy attempt limit', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 2,
      persistRetry: (profileId) => profileId == _profile.id,
    );

    await harness.startDown();

    await waitUntil(() => harness.attempts.length >= 5);
    expect(harness.attempts.take(5).map((a) => a.attempt), [1, 2, 3, 4, 5]);
    expect(
      harness.attempts.take(5).map((a) => a.profileId),
      everyElement(_profile.id),
    );
    // Failures must never look like a reconnected home.
    expect(harness.reconnected, isEmpty);

    await harness.dispose();
  });

  test('without persistRetry the loop gives up at maxAttempts', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 2,
      persistRetry: (_) => false,
    );

    await harness.startDown();

    await waitUntil(() => harness.attempts.length >= 2);
    // Well past several maxDelay windows: a persistent loop would have fired
    // many more attempts by now.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(harness.attempts.map((a) => a.attempt), [1, 2]);
    expect(harness.reconnected, isEmpty);

    await harness.dispose();
  });

  test('onReconnected fires exactly once when a retry succeeds', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 5,
      persistRetry: (profileId) => profileId == _profile.id,
      succeedOnCreate: 4,
    );

    await harness.startDown();

    await waitUntil(() => harness.reconnected.isNotEmpty);
    expect(harness.reconnected, [_profile.id]);
    expect(harness.attempts.map((a) => a.attempt), [1, 2, 3]);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(harness.reconnected, [_profile.id]);
    expect(harness.attempts.map((a) => a.attempt), [1, 2, 3]);

    await harness.dispose();
  });

  test('userDisconnect stops a persistent retry loop', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 1,
      persistRetry: (profileId) => profileId == _profile.id,
    );

    await harness.startDown();
    await waitUntil(() => harness.attempts.length >= 2);

    await harness.coordinator.userDisconnect(_profile.id);
    // Let any attempt already in flight settle before taking the baseline.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final settled = harness.attempts.length;

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(harness.attempts.length, settled);
    expect(harness.reconnected, isEmpty);

    await harness.dispose();
  });

  test('restartReconnect resumes after the loop gave up', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 1,
      persistRetry: (_) => false,
    );

    await harness.startDown();
    await waitUntil(() => harness.attempts.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(harness.attempts.length, 1);

    harness.coordinator.restartReconnect(_profile.id);

    await waitUntil(() => harness.attempts.length >= 2);
    expect(harness.attempts.last.attempt, 1);

    await harness.dispose();
  });

  test('restartReconnect starts a loop for a never-connected home', () async {
    final harness = _ReconnectHarness(maxAttempts: 3);

    // No transport ever opened, so the monitor is still at its initial
    // healthy state; an explicit retry must still start the loop.
    harness.coordinator.restartReconnect(_profile.id);

    await waitUntil(() => harness.reconnected.isNotEmpty);
    expect(harness.attempts.map((a) => a.attempt), [1]);

    await harness.dispose();
  });
}

/// Drives one profile whose first connect succeeds (so a storage client can be
/// opened and closed to trigger the down signal) and whose reconnects fail
/// until [succeedOnCreate].
class _ReconnectHarness {
  _ReconnectHarness({
    required int maxAttempts,
    bool Function(String profileId)? persistRetry,
    this.succeedOnCreate,
  }) {
    final events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        final attempt = createCount;
        if (attempt > 1 &&
            (succeedOnCreate == null || attempt < succeedOnCreate!)) {
          throw StateError('reconnect refused');
        }
        return _InstantAuthClient();
      },
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => _profile,
      policy: SshProfileReconnectPolicy(
        maxAttempts: maxAttempts,
        disconnectCoalesce: const Duration(milliseconds: 5),
        initialDelay: const Duration(milliseconds: 5),
        maxDelay: const Duration(milliseconds: 25),
      ),
      persistRetry: persistRetry,
      onReconnectAttempt: (profileId, attempt) =>
          attempts.add((profileId: profileId, attempt: attempt)),
      onReconnected: reconnected.add,
    );
  }

  /// When set, reconnect creates at or after this count succeed.
  final int? succeedOnCreate;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;
  final List<({String profileId, int attempt})> attempts = [];
  final List<String> reconnected = [];
  var createCount = 0;

  /// Opens the storage plane once, then drops it so the coordinator schedules
  /// its first reconnect.
  Future<void> startDown() async {
    final client = await factory.clientForStorage(_profile);
    client.close();
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
  Future<void> get done async {}
}
