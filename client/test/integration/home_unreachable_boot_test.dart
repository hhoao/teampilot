/// End-to-end contract for an SSH home that is unreachable at cold start:
///
///   bounded first attempt → `unreachable` (no remote boot, only a bounded
///   attempt)
///     → background retry loop → successful reconnect → hot recovery once.
///
/// `buildAppShell` wires the entire production app (storage plane, registries,
/// every cubit) inside a widget tree and is not mountable in `flutter_test`
/// without those planes; earlier tasks confirmed the same. This file therefore
/// has two layers:
///
/// 1. Behavior over the real seam the shell composes (not fakes of the units
///    under test):
///
///      real [HomeConnectAttempt] (fake TCP probe whose reachability flips
///      false → true)
///        + real [HomeConnectionCubit]
///        + real [SshProfileConnectionCoordinator] (fake SSH connector)
///        + a remote-boot counter wired as `onConnected`.
///
/// 2. Source pins for the production wiring that cannot be mounted, following
///    the precedent of `test/app/app_shell_bootstrap_retry_test.dart`: the
///    `deferRemoteBoot` gate, the `onConnected` hot-recovery call, the boot
///    auto-start of the retry loop, and the connect-closure re-arm are read
///    back from `lib/app/app_shell.dart` so deleting any of them fails here.
///
/// This is not `@Tags(['integration'])`: it needs no PTY/Docker and must run
/// in the default suite (which excludes the `integration` tag).
library;

import 'dart:async';
import 'dart:io';
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

const _replacementProfile = SshProfile(
  id: 'home2',
  name: 'replacement',
  host: 'other.example.com',
  port: 2222,
  username: 'bob',
);

class _SwitchableProbe implements TcpReachabilityProbe {
  _SwitchableProbe({required this.reachable, this.reachableHosts = const {}});

  bool reachable;
  final Set<String> reachableHosts;
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
    return reachable || reachableHosts.contains(host);
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

/// Counts invocations of the deferred remote boot wired as `onConnected`.
/// Deliberately dumb: the production idempotency guard lives in the app_shell
/// closure, which is source-pinned below rather than re-modelled here.
class _RemoteBootCounter {
  int runs = 0;
  Future<void>? last;

  Future<void> trigger() => last = _run();

  Future<void> _run() async {
    await pumpEventQueue();
    runs += 1;
  }
}

/// Boot-time wiring shared by every case: the real attempt, cubit, and (when
/// [withCoordinator]) the real reconnect coordinator whose hooks mirror
/// app_shell exactly.
class _HomeBootHarness {
  _HomeBootHarness({
    required bool reachable,
    this.failFirstCreates = 0,
    Set<String> reachableHosts = const {},
  }) : probe = _SwitchableProbe(
         reachable: reachable,
         reachableHosts: reachableHosts,
       ) {
    attempt = HomeConnectAttempt(
      probe: probe,
      resolve: () async {
        resolveCalls += 1;
        return _ctx(fromCache: false);
      },
      cacheContext: () async => cachedContext,
      profileById: (id) => switch (id) {
        'home' => _profile,
        'home2' => _replacementProfile,
        _ => null,
      },
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
      profileResolver: (id) => switch (id) {
        'home' => _profile,
        'home2' => _replacementProfile,
        _ => null,
      },
      policy: SshProfileReconnectPolicy(
        maxAttempts: 5,
        disconnectCoalesce: const Duration(milliseconds: 5),
        initialDelay: const Duration(milliseconds: 5),
        maxDelay: const Duration(milliseconds: 25),
      ),
      onReconnectAttempt: (profileId, attempt) {
        backgroundAttempts.add(attempt);
        if (profileId == activeProfileId) cubit.markBackgroundAttempt(attempt);
      },
      onReconnected: (profileId) {
        // Same guard as app_shell: only a transition into `connected` runs
        // hot recovery.
        if (profileId == activeProfileId &&
            cubit.state.status != HomeConnectionStatus.connected) {
          cubit.markReconnected();
        }
      },
      persistRetry: (profileId) =>
          profileId == activeProfileId &&
          !cubit.isClosed &&
          cubit.state.status != HomeConnectionStatus.connected,
    );
    cubit = HomeConnectionCubit(
      // Mirrors app_shell: the callback reads the live home identity rather
      // than a captured boot id.
      connect: () => attempt.run(activeProfileId),
      cancelRetry: () => coordinator.userDisconnect(activeProfileId),
      resumeRetry: () async {
        // Mirrors app_shell's 「继续重试」: the coordinator is the single retry
        // driver; no competing bounded `connectOnce` runs here.
        coordinator.resumeRetries(activeProfileId);
      },
      onConnected: () {
        unawaited(remoteBoot.trigger());
      },
      profileId: _profile.id,
      host: _profile.host,
      port: _profile.port,
    );
  }

  /// The home id the shell currently targets. Mirrors app_shell's mutable
  /// `activeHomeProfileId` (boot snapshot until a switch updates it).
  String activeProfileId = _profile.id;

  final _SwitchableProbe probe;
  final RuntimeContext cachedContext = _ctx(fromCache: true);
  final int failFirstCreates;
  late final HomeConnectAttempt attempt;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;
  late final HomeConnectionCubit cubit;
  final _RemoteBootCounter remoteBoot = _RemoteBootCounter();
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

  test('retryNow against a reachable host connects and replays the deferred '
      'boot exactly once', () async {
    final harness = _HomeBootHarness(reachable: false);
    addTearDown(harness.dispose);

    harness.seedBoot(await harness.attempt.run(_profile.id));
    expect(harness.cubit.state.status, HomeConnectionStatus.unreachable);
    expect(harness.remoteBoot.runs, 0);

    // Host comes back: the probe flips healthy and the storage connect
    // succeeds.
    harness.probe.reachable = true;

    await harness.cubit.retryNow();
    // `retryNow` hands off to the coordinator; the reconnect completes async.
    await waitUntil(
      () => harness.cubit.state.status == HomeConnectionStatus.connected,
    );
    await harness.remoteBoot.last;

    expect(harness.cubit.state.status, HomeConnectionStatus.connected);
    expect(harness.cubit.state.attempt, 0);
    // The coordinator is the single retry driver: `retryNow` hands off and
    // does not run a second bounded `attempt.run` of its own.
    expect(harness.resolveCalls, 0);
    // One real unreachable → connected transition drives one hot recovery.
    expect(harness.remoteBoot.runs, 1);
  });

  test('the real reconnect loop reconnects the previously unreachable home and '
      'hot-recovers once', () async {
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
    await harness.remoteBoot.last;

    expect(harness.backgroundAttempts, [1, 2, 3]);
    expect(harness.cubit.state.attempt, 0);
    expect(harness.remoteBoot.runs, 1);

    // The loop stopped after success: no further attempt / boot replay.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(harness.backgroundAttempts, [1, 2, 3]);
    expect(harness.remoteBoot.runs, 1);
  });

  test(
    'switching to a reachable home reseeds the cubit and connects the new id',
    () async {
      // Old home is down; only the replacement host answers.
      final harness = _HomeBootHarness(
        reachable: false,
        reachableHosts: {_replacementProfile.host},
      );
      addTearDown(harness.dispose);

      harness.seedBoot(await harness.attempt.run(_profile.id));
      expect(harness.cubit.state.status, HomeConnectionStatus.unreachable);
      expect(harness.cubit.state.profileId, _profile.id);

      // Mirrors switchHomeTarget: the live id moves first, then the cubit is
      // reseeded and one bounded attempt starts against the replacement.
      harness.activeProfileId = _replacementProfile.id;
      harness.cubit.rebind(
        profileId: _replacementProfile.id,
        host: _replacementProfile.host,
        port: _replacementProfile.port,
      );
      expect(harness.cubit.state.status, HomeConnectionStatus.connecting);
      expect(harness.cubit.state.profileId, _replacementProfile.id);

      await harness.cubit.retryNow();
      await waitUntil(
        () => harness.cubit.state.status == HomeConnectionStatus.connected,
      );
      await harness.remoteBoot.last;

      // The gate can now leave the connection page: the cubit is connected and
      // carries the NEW identity, not the abandoned boot-time home.
      expect(harness.cubit.state.status, HomeConnectionStatus.connected);
      expect(harness.cubit.state.profileId, _replacementProfile.id);
      expect(harness.cubit.state.host, _replacementProfile.host);
      expect(harness.cubit.state.port, _replacementProfile.port);
      expect(harness.remoteBoot.runs, 1);
    },
  );

  // `buildAppShell` is unmountable (see file header), so the wiring the
  // behavior cases cannot observe being deleted is pinned at the source
  // level, following `test/app/app_shell_bootstrap_retry_test.dart`.
  // Whitespace is collapsed first so indentation/line breaks do not matter.
  group('app_shell home-resilience wiring (source pins)', () {
    late final String src;

    setUpAll(() {
      src = File(
        'lib/app/app_shell.dart',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    });

    test('an unreachable home defers the remote boot', () {
      expect(
        src,
        contains('final deferRemoteBoot = remoteWorkPlane && !connected;'),
        reason:
            'bootstrapAppData must gate remote boot on the live home '
            'connection, not run it against a dead transport',
      );
      final gate = src.indexOf('if (!deferRemoteBoot) {');
      final bootCall = src.indexOf(
        'showOnboarding = await runRemoteBootAfterConnect();',
        gate,
      );
      final deferredLog = src.indexOf(
        "boot('bootstrapAppData deferred: home unreachable');",
        gate,
      );
      expect(gate, greaterThanOrEqualTo(0));
      expect(
        bootCall,
        greaterThan(gate),
        reason: 'remote boot must be invoked inside the !deferRemoteBoot block',
      );
      expect(
        deferredLog,
        greaterThan(bootCall),
        reason:
            'the unreachable branch must skip remote boot but still finish '
            'boot so StartupGate can paint the connection page',
      );
    });

    test('a successful home connection runs hot recovery', () {
      final onConnected = src.indexOf('onConnected: () {');
      final bootCall = src.indexOf(
        'await runRemoteBootAfterConnect();',
        onConnected,
      );
      // Bound the window to the onConnected block: the same call also appears
      // later in bootstrapAppData (`showOnboarding = await ...`), so without
      // this upper bound deleting the hot-recovery call would still match.
      final afterBoot = src.indexOf(
        'await reconnectHomeSshIfNeeded();',
        onConnected,
      );
      expect(onConnected, greaterThanOrEqualTo(0));
      expect(
        bootCall,
        greaterThan(onConnected),
        reason:
            'HomeConnectionCubit.onConnected must replay the deferred remote '
            'boot through runRemoteBootAfterConnect',
      );
      expect(
        bootCall,
        lessThan(afterBoot),
        reason:
            'the matched call must be the one inside the onConnected block, '
            'not the later bootstrapAppData call',
      );
    });

    test('boot auto-starts the retry loop for an unreachable SSH home', () {
      expect(
        RegExp(
          r'if \(isSshHome && !initialHome\.reachable\) \{ '
          r'sshProfileConnectionCoordinator\.restartReconnect\(homeProfileId\);',
        ).hasMatch(src),
        isTrue,
        reason:
            'a home that never opened a transport emits no close event, so '
            'boot must start the reconnect loop itself',
      );
    });

    test('a failed bounded connect re-arms the retry loop', () {
      expect(
        RegExp(
          r'if \(!result\.reachable && id != null\) \{ '
          r'sshProfileConnectionCoordinator\.restartReconnect\(id\);',
        ).hasMatch(src),
        isTrue,
        reason:
            'an explicit retry whose bounded resolve still fails must leave '
            'something retrying behind the connection page (for the CURRENT '
            'home id, not the boot snapshot)',
      );
    });

    test('a home switch reseeds the connection cubit and retries the new '
        'target', () {
      final switchFn = src.indexOf(
        'Future<void> switchHomeTarget(String id) async {',
      );
      expect(switchFn, greaterThanOrEqualTo(0));
      final rebind = src.indexOf('cubit.rebind(', switchFn);
      final retry = src.indexOf('unawaited(cubit.retryNow());', switchFn);
      final transport = src.indexOf(
        'await applyHomeEventTransport(restart: true);',
        switchFn,
      );
      expect(
        rebind,
        greaterThan(switchFn),
        reason:
            'switchHomeTarget must reseed the cubit onto the selected home '
            'instead of leaving it closed over the boot-time id',
      );
      expect(
        retry,
        greaterThan(rebind),
        reason:
            'the reseeded cubit must start a bounded attempt so the gate can '
            'leave the connection page once the new home connects',
      );
      expect(
        transport,
        greaterThan(retry),
        reason:
            'the bounded retry belongs to the switch, before transport '
            'restart',
      );
    });

    test('cubit/coordinator hooks read the live home id', () {
      expect(
        src,
        contains('profileId == activeHomeProfileId'),
        reason:
            'onReconnectAttempt/onReconnected/persistRetry must follow home '
            'switches, not the captured boot id',
      );
      expect(
        src,
        contains('final id = activeHomeProfileId;'),
        reason: 'the connect/resume/cancel callbacks must resolve the live id',
      );
    });

    test('recovery rebinds the storage plane instead of using the native '
        'fallback', () {
      expect(
        src,
        contains('homeRecoveredOntoNativeFallback()'),
        reason: 'recovery must detect the boot-time native fallback plane',
      );
      expect(
        src,
        contains('runSelfInitiatedSwap('),
        reason:
            'the SSH plane must be published through the invalidation '
            'service so the swap echo does not schedule a duplicate reload',
      );
      expect(
        src,
        contains('markUnreachable(failure)'),
        reason:
            'when the plane cannot be rebound the gate must stay on the '
            'connection page with an actionable error instead of operating on '
            'local storage or asking for a restart',
      );
    });

    test('editing the current home profile re-arms a bounded retry', () {
      expect(
        src,
        contains('sshProfileCubit.stream.listen'),
        reason:
            'a saved host/port edit must be observed without a callback from '
            'the editor widgets',
      );
      expect(
        src,
        contains('sshProfileConnectivityKey('),
        reason:
            'the watch must compare reachability-relevant identity fields, '
            'not path-cache writes',
      );
      expect(
        src,
        contains('watchedHomeProfileConnectivityKey'),
        reason: 'the listener re-arms only after the current profile changed',
      );
    });
  });
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
