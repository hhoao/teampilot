import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/ssh/ssh_transport_close.dart';
import 'package:teampilot/services/ssh/ssh_transport_close_policy.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';

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

  test('resumeRetries clears the latch and retries again', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 2,
      persistRetry: (profileId) => profileId == _profile.id,
    );

    await harness.startDown();
    await waitUntil(() => harness.attempts.length >= 2);

    await harness.coordinator.userDisconnect(_profile.id);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final paused = harness.attempts.length;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(harness.attempts.length, paused);

    // 「继续重试」 resumes through the coordinator (single driver) — no parallel
    // `userConnect`, so it cannot race a `Duplicate SSH worker request id`.
    harness.coordinator.resumeRetries(_profile.id);
    await waitUntil(() => harness.attempts.length > paused);

    await harness.dispose();
  });

  test('hostIdentityChanged is classified as non-retryable', () {
    const changed = SshTransportClosed(
      reason: SshTransportCloseReason.hostIdentityChanged,
      plane: SshTransportPlane.storage,
    );
    expect(isNonRetryableTransportClose(changed), isTrue);
    expect(
      SshTransportClosePolicy.evaluate(changed).scheduleStorageReconnect,
      isFalse,
    );
    // A plain network fault must stay retryable (the home resilience case).
    const transient = SshTransportClosed(
      reason: SshTransportCloseReason.transportError,
      plane: SshTransportPlane.storage,
    );
    expect(isNonRetryableTransportClose(transient), isFalse);
    expect(
      SshTransportClosePolicy.evaluate(transient).scheduleStorageReconnect,
      isTrue,
    );
  });

  test('hostIdentityChanged stops the loop even with persistRetry', () async {
    final stopped = <String>[];
    final harness = _ReconnectHarness(
      maxAttempts: 3,
      // Unbounded: before the fix this looped forever on every close.
      persistRetry: (_) => true,
      onNonRetryableClose: (profileId, _) => stopped.add(profileId),
    );
    addTearDown(harness.dispose);

    await harness.startDown();
    await waitUntil(() => harness.attempts.isNotEmpty);

    harness.emitHostIdentityChanged();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final settled = harness.attempts.length;

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(harness.attempts.length, settled);
    expect(stopped, [_profile.id]);
  });

  test('a local profile edit close keeps the profile retryable', () async {
    // Regression: editing a profile host retired the stale lease as
    // `hostIdentityChanged`, so this callback fired, the coordinator
    // latched the profile, and the home page went back to `unreachable`
    // even though the new host had already reconnected.
    final stopped = <String>[];
    final harness = _ReconnectHarness(
      maxAttempts: 3,
      persistRetry: (_) => true,
      onNonRetryableClose: (profileId, _) => stopped.add(profileId),
    );
    addTearDown(harness.dispose);

    await harness.startDown();
    await waitUntil(() => harness.attempts.isNotEmpty);

    harness.emitStorageClose(SshTransportCloseReason.profileInvalidated);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      stopped,
      isEmpty,
      reason: 'a local re-target must not be a permanent failure',
    );
    expect(
      harness.coordinator.isUserDisconnectLatched(_profile.id),
      isFalse,
      reason: 'an edited profile must not be latched into suspension',
    );
  });

  test('home switch cancellation stops the abandoned profile loop', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 3,
      // Unbounded: without the switch cancellation this would retry forever.
      persistRetry: (_) => true,
    );

    await harness.startDown();
    await waitUntil(() => harness.attempts.length >= 2);

    // Mirrors switchHomeTarget: latch the abandoned profile (in-flight attempts
    // back out) and drop its pending timer/counter.
    await harness.coordinator.userDisconnect(_profile.id);
    harness.coordinator.resetReconnectAttempts(_profile.id);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    final settled = harness.attempts.length;
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(harness.attempts.length, settled);
    expect(harness.coordinator.isUserDisconnectLatched(_profile.id), isTrue);
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

  test('a throwing reconnect hook cannot wedge later attempts', () async {
    final harness = _ReconnectHarness(
      maxAttempts: 5,
      persistRetry: (_) => true,
      succeedOnCreate: 4,
      // The first attempt throws from the progress hook, before the transport
      // work. Without the try/finally guard `_reconnectInFlight` would stay
      // latched and no later attempt would ever run.
      beforeAttempt: (_, _) => throw StateError('hook boom'),
    );

    await harness.startDown();
    await waitUntil(() => harness.attempts.length >= 3);

    expect(harness.attempts.take(3).map((a) => a.attempt), [1, 2, 3]);

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

  test(
    'boot-unreachable seed reconnects through the cubit automatically',
    () async {
      var onConnectedCalls = 0;
      final cubit = HomeConnectionCubit(
        connect: () async =>
            const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
        cancelRetry: () async {},
        resumeRetry: () async {},
        onConnected: () => onConnectedCalls += 1,
        profileId: _profile.id,
      );
      addTearDown(cubit.close);
      final reconnectingAttempts = <int>[];
      final subscription = cubit.stream.listen((state) {
        if (state.status == HomeConnectionStatus.reconnecting) {
          reconnectingAttempts.add(state.attempt);
        }
      });
      addTearDown(subscription.cancel);

      final harness = _ReconnectHarness(
        maxAttempts: 5,
        failFirstCreates: 2,
        homeCubit: cubit,
      );
      addTearDown(harness.dispose);

      // Seeded like a cold boot whose first bounded attempt failed.
      cubit.markInitial(
        const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      );
      expect(cubit.state.status, HomeConnectionStatus.unreachable);

      // Mirrors the boot auto-start in app_shell.
      harness.coordinator.restartReconnect(_profile.id);

      await waitUntil(
        () => cubit.state.status == HomeConnectionStatus.connected,
      );
      // Every attempt onset surfaces as progress; the third attempt succeeds.
      expect(harness.attempts.map((a) => a.attempt), [1, 2, 3]);
      expect(reconnectingAttempts, [1, 2, 3]);
      expect(onConnectedCalls, 1);
      expect(cubit.state.attempt, 0);
    },
  );
}

/// Drives one profile whose first connect succeeds (so a storage client can be
/// opened and closed to trigger the down signal) and whose reconnects fail
/// until [succeedOnCreate].
class _ReconnectHarness {
  _ReconnectHarness({
    required int maxAttempts,
    bool Function(String profileId)? persistRetry,
    this.succeedOnCreate,
    this.failFirstCreates,
    this.homeCubit,
    this.beforeAttempt,
    this.onNonRetryableClose,
  }) {
    final events = SshConnectionEvents();
    this.events = events;
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        final attempt = createCount;
        if (failFirstCreates != null) {
          if (attempt <= failFirstCreates!) {
            throw StateError('reconnect refused');
          }
          return _InstantAuthClient();
        }
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
      persistRetry: persistRetry ?? _persistWhileHomeNotConnected,
      onReconnectAttempt: (profileId, attempt) {
        attempts.add((profileId: profileId, attempt: attempt));
        beforeAttempt?.call(profileId, attempt);
        homeCubit?.markBackgroundAttempt(attempt);
      },
      onReconnected: (profileId) {
        reconnected.add(profileId);
        final cubit = homeCubit;
        // Same guard as app_shell: only a transition into `connected` runs
        // hot recovery.
        if (cubit != null &&
            cubit.state.status != HomeConnectionStatus.connected) {
          cubit.markReconnected();
        }
      },
      onNonRetryableClose: onNonRetryableClose,
    );
  }

  /// When set, reconnect creates at or after this count succeed.
  final int? succeedOnCreate;

  /// When set, every create up to and including this count fails, so a test
  /// can start the loop without first opening a client.
  final int? failFirstCreates;

  /// Optional cubit wired exactly like app_shell's home hooks.
  final HomeConnectionCubit? homeCubit;

  /// Runs inside `onReconnectAttempt`; a throw here must not wedge the loop.
  final void Function(String profileId, int attempt)? beforeAttempt;
  final SshNonRetryableCloseHandler? onNonRetryableClose;
  late final SshConnectionEvents events;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;
  final List<({String profileId, int attempt})> attempts = [];
  final List<String> reconnected = [];
  var createCount = 0;

  bool _persistWhileHomeNotConnected(String profileId) {
    final cubit = homeCubit;
    return cubit != null &&
        !cubit.isClosed &&
        profileId == _profile.id &&
        cubit.state.status != HomeConnectionStatus.connected;
  }

  /// Opens a member plane once, then drops it so the coordinator schedules its
  /// first reconnect.
  Future<void> startDown() async {
    final client = await factory.createMemberClient(_profile);
    client.close();
  }

  /// Emits a permanent host-identity change on the storage plane (the signal
  /// that used to spawn an endless reconnect loop).
  void emitHostIdentityChanged() =>
      emitStorageClose(SshTransportCloseReason.hostIdentityChanged);

  /// Emits a storage-plane close with [reason].
  void emitStorageClose(SshTransportCloseReason reason) {
    events.onTransportClosed?.call(
      _profile.id,
      SshTransportClosed(reason: reason, plane: SshTransportPlane.storage),
      StackTrace.empty,
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
  Future<void> get done async {}
}
