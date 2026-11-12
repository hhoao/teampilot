import 'dart:async';

import '../../models/ssh_profile.dart';
import '../remote/remote_connection_monitor.dart';
import 'ssh_client_factory.dart';
import 'ssh_connection_events.dart';
import 'ssh_connection_failure.dart';
import 'ssh_connection_gate.dart';
import 'ssh_home_connectivity_state.dart';
import 'ssh_profile_connection_coordinator.dart';
import 'ssh_profile_reconnect_policy.dart';

export 'ssh_home_connectivity_state.dart'
    show SshHomeConnectivityState, SshPhase, SshFailureKind;

/// App-level single owner of SSH home connectivity. Pure Dart: no
/// flutter_bloc import. Publishes one state stream and drives the gate.
///
/// State priority mirrors the connection cubit's former _resolveStatus:
/// a live storage lease (up) > an in-flight dial (connecting) > a monitor
/// reconnecting > a sticky connect failure > unreachable. A live lease wins
/// over monitor noise, so heartbeat churn never blanks a healthy home.
class SshHomeConnectivitySupervisor implements SshConnectivitySource {
  SshHomeConnectivitySupervisor({
    required SshClientFactory factory,
    required SshConnectionEvents events,
    required SshProfileResolver profileResolver,
    required SshConnectionGate gate,
    SshProfileReconnectPolicy policy = const SshProfileReconnectPolicy(),
    SshProfileDisconnectHandler? onDisconnect,
    SshSessionPlaneReconnectHandler? onReconnectSessionPlane,
    Future<void> Function(SshProfile)? dialProfile,
  }) : _factory = factory,
       _gate = gate,
       _dialProfile = dialProfile ??
           ((profile) => factory.ensureStorageConnected(profile)) {
    _coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: profileResolver,
      gate: gate,
      dial: dial,
      policy: policy,
      onDisconnect: onDisconnect,
      onReconnectSessionPlane: onReconnectSessionPlane,
      onReconnectAttempt: noteReconnectAttempt,
      onReconnected: noteReconnected,
      onNonRetryableClose: noteNonRetryableClose,
      persistRetry: shouldPersistRetry,
    );
    _poolSub = factory.storagePoolChanges.listen(_onPoolChanged);
  }

  final SshClientFactory _factory;
  final SshConnectionGate _gate;
  final Future<void> Function(SshProfile) _dialProfile;
  late final SshProfileConnectionCoordinator _coordinator;

  final Map<String, SshHomeConnectivityState> _states = {};
  final Map<String, StreamSubscription<RemoteConnectionState>> _monitorSubs = {};
  final Map<String, Future<void>> _dialInFlight = {};
  final _changes = StreamController<SshHomeConnectivityState>.broadcast();
  StreamSubscription<String>? _poolSub;
  String? _activeHomeId;
  var _planeRebinding = false;
  var _disposed = false;

  @override
  Stream<SshHomeConnectivityState> get changes => _changes.stream;

  Stream<SshHomeConnectivityState> changesFor(String id) =>
      _changes.stream.where((s) => s.profileId == id);

  @override
  SshHomeConnectivityState stateFor(String id) {
    final stored = _states[id];
    if (stored != null) return stored;
    // A pool that became live before this profile was ever observed (e.g. a
    // cold-boot seed or an external clientForStorage) is already connected.
    // Derive it on read so the projection never reports a live lease as idle.
    if (_factory.hasLiveStorageClient(id)) {
      return SshHomeConnectivityState.up(id);
    }
    return SshHomeConnectivityState(profileId: id);
  }

  SshIoGuard get ioGuard => _gate.beforeIo;
  SshConnectionGate get gate => _gate;

  /// DI compatibility: main.dart and workspace_terminal_panel.dart read this
  /// coordinator type. Owned here, never constructed elsewhere.
  SshProfileConnectionCoordinator get coordinator => _coordinator;

  Future<void> awaitAvailable(String id) => _gate.waitUntilUp(id);

  /// Reads supervisor state, never a cubit's status (invariant 4).
  bool shouldPersistRetry(String id) =>
      id == _activeHomeId && !stateFor(id).isUp;

  /// The single write path. Command entry points (cubit connect/disconnect)
  /// and internal signals all funnel through here; dedup keeps the stream
  /// quiet and makes the `up` transition atomic (invariant 3).
  @override
  void publish(SshHomeConnectivityState state) {
    if (_disposed || _changes.isClosed) return;
    final id = state.profileId;
    // Lazily observe this profile's monitor so direct monitorFor(...) changes
    // from the retry driver re-derive and publish.
    _monitorSubs.putIfAbsent(
      id,
      () => _coordinator.changesFor(id).listen((_) => _onMonitorChanged(id)),
    );
    if (_states[id] == state) return;
    _states[id] = state;
    _changes.add(state);
  }

  // --- coordinator hook surface ---

  void noteReconnectAttempt(String id, int attempt) => publish(
    stateFor(id).copyWith(
      phase: SshPhase.reconnecting,
      attempt: attempt,
      storageLive: false,
    ),
  );

  void noteReconnected(String id) {
    _gate.markUp(id);
    publish(SshHomeConnectivityState.up(id));
  }

  void noteNonRetryableClose(String id, Object error) {
    final failure = isSshHostKeyFailure(error)
        ? SshFailureKind.hostIdentityChanged
        : isSshAuthFailure(error)
        ? SshFailureKind.authFailed
        : SshFailureKind.transportError;
    publish(
      stateFor(id).copyWith(
        phase: SshPhase.failed,
        failure: failure,
        storageLive: false,
      ),
    );
  }

  // --- commands ---

  /// Subscribes to a profile's monitor so future liveness changes are
  /// observed. Deliberately does NOT emit a speculative derived state: at boot
  /// an SSH home may already be seeded `connected` by `markInitial`, and a
  /// cold-pool `unreachable` emission here would knock it back to the retry
  /// page before any real transport close occurred (the original bug).
  void observeProfile(String id) {
    _monitorSubs.putIfAbsent(
      id,
      () => _coordinator.changesFor(id).listen((_) => _onMonitorChanged(id)),
    );
  }

  void activateHome(String? id) {
    final previous = _activeHomeId;
    if (previous != null && previous != id) {
      unawaited(_coordinator.userDisconnect(previous));
      _coordinator.resetReconnectAttempts(previous);
    }
    _activeHomeId = id;
    if (id != null) observeProfile(id);
  }

  /// A local re-target (edited host) starts a fresh dial. Publish an explicit
  /// `connecting` (never `failed`, invariant 5) and clear any stale failure so
  /// the edit stays retryable — the 9c82e0c45 behaviour.
  void profileEdited(String id) {
    _gate.resume(id);
    _coordinator.resetReconnectAttempts(id);
    publish(
      stateFor(id).copyWith(
        phase: SshPhase.connecting,
        attempt: 0,
        storageLive: false,
        clearFailure: true,
        clearErrorDetail: true,
      ),
    );
  }

  void holdPlaneRebind() {
    _planeRebinding = true;
    final id = _activeHomeId;
    if (id != null) _emit(id);
  }

  void releasePlaneRebind() {
    _planeRebinding = false;
    final id = _activeHomeId;
    if (id != null) _emit(id);
  }

  Future<void> userConnect(SshProfile profile) {
    // Optimistic connecting so the progress surface appears before the dial.
    // Skip it when a dial is already in flight: a concurrent second call would
    // otherwise republish `connecting` on top of the first dial's `up`.
    if (!_dialInFlight.containsKey(profile.id)) {
      publish(
        stateFor(profile.id).copyWith(
          phase: SshPhase.connecting,
          attempt: 0,
          storageLive: false,
          clearFailure: true,
          clearErrorDetail: true,
        ),
      );
    }
    return _coordinator.userConnect(profile);
  }

  Future<void> userDisconnect(String id) {
    publish(
      stateFor(id).copyWith(
        phase: SshPhase.suspended,
        attempt: 0,
        storageLive: false,
      ),
    );
    return _coordinator.userDisconnect(id);
  }

  void resumeRetries(String id) => _coordinator.resumeRetries(id);
  void resetReconnectAttempts(String id) =>
      _coordinator.resetReconnectAttempts(id);
  void restartReconnect(String id) => _coordinator.restartReconnect(id);

  // --- internal derivation ---

  void _onPoolChanged(String id) {
    final live = _factory.hasLiveStorageClient(id);
    if (live) {
      _gate.markUp(id);
      publish(SshHomeConnectivityState.up(id).copyWith(
        planeRebinding: _planeRebinding && id == _activeHomeId,
      ));
    } else {
      _emit(id);
    }
  }

  void _onMonitorChanged(String id) => _emit(id);

  void _emit(String id) => publish(_derive(id));

  SshHomeConnectivityState _derive(String id) {
    final previous = stateFor(id);
    final live = _factory.hasLiveStorageClient(id);
    final monitor = _coordinator.monitorFor(id).state.status;

    // The durable truth is the live lease, not the dial-permission gate: a
    // gate left `up` after the lease was evicted must not claim connected.
    // A live lease beats a connecting dial, monitor noise and any sticky
    // failure, and the `up` value clears them atomically (invariant 3).
    if (live) {
      return SshHomeConnectivityState.up(id).copyWith(
        planeRebinding: _planeRebinding && id == _activeHomeId,
      );
    }
    // An in-flight dial keeps the connecting surface until success/failure.
    if (previous.phase == SshPhase.connecting) {
      return previous.copyWith(storageLive: false);
    }
    if (monitor == RemoteConnectionStatus.reconnecting) {
      return previous.copyWith(
        phase: SshPhase.reconnecting,
        storageLive: false,
      );
    }
    // Sticky connect failure survives cold-pool events until a real `up`.
    if (previous.phase == SshPhase.failed) {
      return previous.copyWith(storageLive: false);
    }
    if (_gate.stateOf(id) == SshConnectionGateState.suspended) {
      return previous.copyWith(
        phase: SshPhase.suspended,
        storageLive: false,
      );
    }
    return previous.copyWith(
      phase: SshPhase.unreachable,
      storageLive: false,
    );
  }

  /// Single-flight dial. The coordinator's userConnect and reconnect routes
  /// both call this, so only one clientFor exists at a time (invariant 1).
  /// It does not publish `connecting`: userConnect already did, and a retry
  /// dial must keep the `reconnecting` surface from noteReconnectAttempt.
  Future<void> dial(SshProfile profile) {
    final existing = _dialInFlight[profile.id];
    if (existing != null) return existing;
    _gate.markConnecting(profile.id);
    // The callback body MUST stay `void`. An expression-bodied
    // `() => _dialInFlight.remove(id)` would return the removed Future, and
    // `whenComplete` waits for a returned Future — deadlocking on the very
    // future it is completing.
    final future = _dialProfile(profile).whenComplete(() {
      _dialInFlight.remove(profile.id);
    });
    _dialInFlight[profile.id] = future;
    return future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _poolSub?.cancel();
    for (final sub in _monitorSubs.values) {
      await sub.cancel();
    }
    _monitorSubs.clear();
    _dialInFlight.clear();
    await _coordinator.dispose();
    await _changes.close();
    _gate.dispose();
  }
}
