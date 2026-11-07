@Tags(['integration'])
library;

/// End-to-end contract for an SSH home that is unreachable at cold start:
///
///   bounded first attempt → `unreachable` (no remote boot, no splash wait)
///     → background retry loop → successful reconnect → hot recovery once.
///
/// `buildAppShell` wires the entire production app (storage plane, registries,
/// every cubit) inside a widget tree and is not mountable in `flutter_test`
/// without those planes; earlier tasks confirmed the same. This test therefore
/// exercises the real seam the shell composes instead of a fake of it:
///
///   real [HomeConnectAttempt] (fake TCP probe whose reachability flips
///   false → true)
///     + real [HomeConnectionCubit]
///     + real [SshProfileConnectionCoordinator] (fake SSH connector)
///     + the deferred "remote boot" counter wired as `onConnected`.
///
/// The only reproduction is the idempotent single-flight runner, which mirrors
/// `runRemoteBootAfterConnect` in app_shell (completed flag + in-flight
/// coalescing). That runner is what makes "exactly once, even if a late
/// duplicate success arrives" observable at this level.

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/ssh/tcp_reachability_probe.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

const _profile = SshProfile(
  id: 'home',
  name: 'dev',
  host: 'home.example.com',
  port: 22,
  username: 'alice',
);

class _SwitchableProbe implements TcpReachabilityProbe {
  _SwitchableProbe({required this.reachable});

  bool reachable;
  int calls = 0;
  final List<Duration> timeouts = [];

  @override
  Future<bool> isReachable(
    String host,
    int port, {
    required Duration timeout,
  }) async {
    calls += 1;
    timeouts.add(timeout);
    return reachable;
  }
}

RuntimeContext _ctx({required bool fromCache}) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: InMemoryFilesystem(),
  home: '/home/alice',
  cwd: '/home/alice',
  appDataRoot: '/home/alice/.teampilot',
  paths: const AppPaths('/home/alice/.teampilot'),
  pathsFromCache: fromCache,
);

/// Mirrors `runRemoteBootAfterConnect` in app_shell: the deferred chain runs
/// once per successful home connection, coalescing concurrent callers and
/// retiring after it completes.
class _DeferredRemoteBoot {
  int runs = 0;
  bool _completed = false;
  Future<void>? _inFlight;

  Future<void> run() {
    if (_completed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _runOnce();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _runOnce() async {
    await pumpEventQueue();
    runs += 1;
    _completed = true;
  }
}

/// Boot-time wiring shared by every case: the real attempt, cubit, and (when
/// [withCoordinator]) the real reconnect coordinator whose hooks mirror
/// app_shell exactly.
class _HomeBootHarness {
  _HomeBootHarness({required bool reachable, this.failFirstCreates = 0})
    : probe = _SwitchableProbe(reachable: reachable) {
    attempt = HomeConnectAttempt(
      probe: probe,
      resolve: () async {
        resolveCalls += 1;
        return _ctx(fromCache: false);
      },
      cacheContext: () async => cachedContext,
      profileById: (id) => id == _profile.id ? _profile : null,
    );

    final events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        createCount += 1;
        // Models the server refusing until it comes back: attempt N fails for
        // N <= failFirstCreates and succeeds afterwards.
        if (createCount <= failFirstCreates) {
          throw StateError('reconnect refused');
        }
        return _InstantAuthClient();
      },
    );

    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (id) => id == _profile.id ? _profile : null,
      policy: SshProfileReconnectPolicy(
        maxAttempts: 5,
        disconnectCoalesce: const Duration(milliseconds: 5),
        initialDelay: const Duration(milliseconds: 5),
        maxDelay: const Duration(milliseconds: 25),
      ),
      onReconnectAttempt: (profileId, attempt) {
        backgroundAttempts.add(attempt);
        if (profileId == _profile.id) cubit.markBackgroundAttempt(attempt);
      },
      onReconnected: (profileId) {
        // Same guard as app_shell: only a transition into `connected` runs
        // hot recovery.
        if (profileId == _profile.id &&
            cubit.state.status != HomeConnectionStatus.connected) {
          cubit.markReconnected();
        }
      },
      persistRetry: (profileId) =>
          profileId == _profile.id &&
          !cubit.isClosed &&
          cubit.state.status != HomeConnectionStatus.connected,
    );
    cubit = HomeConnectionCubit(
      connect: () => attempt.run(_profile.id),
      cancelRetry: () => coordinator.userDisconnect(_profile.id),
      resumeRetry: () async {
        // Mirrors app_shell's 「继续重试」: clear the spent window, open the
        // storage plane, and re-arm the loop if the manual connect fails.
        coordinator.resetReconnectAttempts(_profile.id);
        try {
          await coordinator.userConnect(_profile);
        } on Object {
          coordinator.restartReconnect(_profile.id);
          rethrow;
        }
      },
      onConnected: () {
        lastBoot = remoteBoot.run();
      },
      profileId: _profile.id,
      host: _profile.host,
      port: _profile.port,
    );
  }

  final _SwitchableProbe probe;
  final RuntimeContext cachedContext = _ctx(fromCache: true);
  final int failFirstCreates;
  late final HomeConnectAttempt attempt;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;
  late final HomeConnectionCubit cubit;
  final _DeferredRemoteBoot remoteBoot = _DeferredRemoteBoot();
  Future<void>? lastBoot;
  int createCount = 0;
  int resolveCalls = 0;
  final List<int> backgroundAttempts = [];

  /// Seeds the cubit exactly like app_shell's `markInitial(initialHome)`.
  void seedBoot(HomeConnectResult result) => cubit.markInitial(result);

  /// Mirrors app_shell's auto-start of the retry loop when boot found the
  /// home unreachable (no transport was ever opened, so no close event can
  /// start the loop).
  void startBootRetryLoop() => coordinator.restartReconnect(_profile.id);

  Future<void> dispose() async {
    await cubit.close();
    await coordinator.dispose();
  }
}

void main() {
  test(
    'unreachable home at boot fails fast without running the deferred boot',
    () async {
      final harness = _HomeBootHarness(reachable: false);
      addTearDown(harness.dispose);

      final stopwatch = Stopwatch()..start();
      final result = await harness.attempt.run(_profile.id);
      stopwatch.stop();

      expect(result.reachable, isFalse);
      expect(result.errorKind, HomeErrorKind.tcpUnreachable);
      // The cached plane is carried so the shell can paint paths offline.
      expect(result.context, same(harness.cachedContext));

      harness.seedBoot(result);
      expect(harness.cubit.state.status, HomeConnectionStatus.unreachable);
      expect(harness.cubit.state.lastErrorKind, HomeErrorKind.tcpUnreachable);

      // The TCP gate short-circuits the SSH resolve: no remote I/O ran, so the
      // deferred remote boot must not have been invoked at all.
      expect(harness.probe.calls, 1);
      expect(harness.probe.timeouts.single, const Duration(seconds: 2));
      expect(harness.resolveCalls, 0);
      expect(harness.remoteBoot.runs, 0);
      // Bounded fail-fast: nowhere near the old ~17s×N splash stall.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test(
    'retryNow against a reachable host connects and replays the deferred '
    'boot exactly once',
    () async {
      final harness = _HomeBootHarness(reachable: false);
      addTearDown(harness.dispose);

      harness.seedBoot(await harness.attempt.run(_profile.id));
      expect(harness.cubit.state.status, HomeConnectionStatus.unreachable);
      expect(harness.remoteBoot.runs, 0);

      // Host comes back: the probe flips healthy and the storage connect
      // succeeds.
      harness.probe.reachable = true;

      await harness.cubit.retryNow();
      await harness.lastBoot;

      expect(harness.cubit.state.status, HomeConnectionStatus.connected);
      expect(harness.cubit.state.attempt, 0);
      expect(harness.resolveCalls, 1);
      expect(harness.remoteBoot.runs, 1);

      // A late duplicate success (e.g. the coordinator finishing after the
      // cubit already connected) must not replay the remote boot.
      harness.cubit.markReconnected();
      await harness.lastBoot;
      expect(harness.remoteBoot.runs, 1);

      await harness.cubit.connectOnce();
      await harness.lastBoot;
      expect(harness.cubit.state.status, HomeConnectionStatus.connected);
      expect(harness.resolveCalls, 2);
      expect(harness.remoteBoot.runs, 1);
    },
  );

  test(
    'the real reconnect loop reconnects the previously unreachable home and '
    'hot-recovers once',
    () async {
      // The first two SSH creates are refused (host still down), the third
      // succeeds — the background loop must keep going and then recover.
      final harness = _HomeBootHarness(reachable: false, failFirstCreates: 2);
      addTearDown(harness.dispose);

      harness.seedBoot(await harness.attempt.run(_profile.id));
      expect(harness.cubit.state.status, HomeConnectionStatus.unreachable);

      // Cold boot found the home down: the shell starts the loop itself.
      harness.startBootRetryLoop();

      // Failed background attempts surface as `reconnecting` progress.
      await waitUntil(() => harness.backgroundAttempts.length >= 2);
      expect(harness.cubit.state.status, HomeConnectionStatus.reconnecting);
      expect(harness.cubit.state.attempt, greaterThanOrEqualTo(1));
      expect(harness.remoteBoot.runs, 0);

      // The next attempt succeeds and hot recovery runs once.
      await waitUntil(
        () => harness.cubit.state.status == HomeConnectionStatus.connected,
      );
      await harness.lastBoot;

      expect(harness.backgroundAttempts, [1, 2, 3]);
      expect(harness.cubit.state.attempt, 0);
      expect(harness.remoteBoot.runs, 1);

      // The loop stopped after success: no further attempt / boot replay.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(harness.backgroundAttempts, [1, 2, 3]);
      expect(harness.remoteBoot.runs, 1);
    },
  );
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSshSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}
}

class _FakeSshSocket implements SSHSocket {
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
