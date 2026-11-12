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
  SshHomeConnectivityState stateFor(String id) =>
      _states[id] ?? SshHomeConnectivityState(profileId: id);

  SshIoGuard get ioGuard => _gate.beforeIo;
  SshConnectionGate get gate => _gate;

  /// DI compatibility: main.dart and workspace_terminal_panel.dart read this
  /// coordinator type. Owned here, never constructed elsewhere.
  SshProfileConnectionCoordinator get coordinator => _coordinator;

  Future<void> awaitAvailable(String id) => _gate.waitUntilUp(id);

  /// Reads supervisor state, never a cubit's status (invariant 4).
  bool shouldPersistRetry(String id) =>
      id == _activeHomeId && !stateFor(id).isUp;

  // --- coordinator hook surface (all state writes funnel through _publish) ---

  void noteReconnectAttempt(String id, int attempt) => _publish(
    id,
    stateFor(id).copyWith(phase: SshPhase.reconnecting, attempt: attempt),
  );

  void noteReconnected(String id) {
    _gate.markUp(id);
    _emit(id);
  }

  void noteNonRetryableClose(String id, Object error) {
    final failure = isSshHostKeyFailure(error)
        ? SshFailureKind.hostIdentityChanged
        : isSshAuthFailure(error)
        ? SshFailureKind.authFailed
        : SshFailureKind.transportError;
    _publish(
      id,
      stateFor(id).copyWith(
        phase: SshPhase.failed,
        failure: failure,
        storageLive: false,
      ),
    );
  }

  // --- commands ---

  void observeProfile(String id) {
    _monitorSubs.putIfAbsent(
      id,
      () => _coordinator.changesFor(id).listen((_) => _emit(id)),
    );
    // Always re-derive: gate has no onUp callback (D3).
    _emit(id);
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

  void profileEdited(String id) {
    _gate.resume(id);
    _coordinator.resetReconnectAttempts(id);
    // A local re-target starts a fresh dial. Publish an explicit `connecting`
    // (never `failed`, invariant 5) and clear any stale failure so the edit
    // stays retryable — the 9c82e0c45 behaviour.
    _publish(
      id,
      stateFor(id).copyWith(
        phase: SshPhase.connecting,
        attempt: 0,
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

  Future<void> userConnect(SshProfile profile) =>
      _coordinator.userConnect(profile);
  Future<void> userDisconnect(String id) => _coordinator.userDisconnect(id);
  void resumeRetries(String id) => _coordinator.resumeRetries(id);
  void resetReconnectAttempts(String id) =>
      _coordinator.resetReconnectAttempts(id);
  void restartReconnect(String id) => _coordinator.restartReconnect(id);

  void _onPoolChanged(String id) {
    final live = _factory.hasLiveStorageClient(id);
    if (live) _gate.markUp(id);
    _emit(id);
  }

  void _emit(String id) => _publish(id, _derive(id));

  void _publish(String id, SshHomeConnectivityState next) {
    if (_disposed || _changes.isClosed || _states[id] == next) return;
    _states[id] = next;
    _changes.add(next);
  }

  SshHomeConnectivityState _derive(String id) {
    final previous = stateFor(id);
    final gateState = _gate.stateOf(id);
    final monitor = _coordinator.monitorFor(id).state.status;
    final live = _factory.hasLiveStorageClient(id);
    final isActiveHome = id == _activeHomeId;

    final phase = switch (gateState) {
      SshConnectionGateState.suspended => SshPhase.suspended,
      SshConnectionGateState.down =>
        monitor == RemoteConnectionStatus.reconnecting
            ? SshPhase.reconnecting
            : SshPhase.unreachable,
      SshConnectionGateState.connecting => SshPhase.connecting,
      SshConnectionGateState.up => SshPhase.up,
      SshConnectionGateState.idle =>
        monitor == RemoteConnectionStatus.reconnecting
            ? SshPhase.reconnecting
            : SshPhase.idle,
    };

    if (phase == SshPhase.up) {
      // Single atomic value: never carries a stale failure (invariant 3).
      return SshHomeConnectivityState.up(id).copyWith(
        planeRebinding: _planeRebinding && isActiveHome,
      );
    }
    return previous.copyWith(
      phase: phase,
      storageLive: live || gateState == SshConnectionGateState.up,
      planeRebinding: _planeRebinding && isActiveHome,
      clearFailure: phase == SshPhase.connecting,
    );
  }

  /// Single-flight dial. Task 4 routes coordinator's userConnect/reconnect
  /// through this so only one clientFor exists at a time (invariant 1).
  Future<void> dial(SshProfile profile) {
    final existing = _dialInFlight[profile.id];
    if (existing != null) return existing;
    _gate.markConnecting(profile.id);
    final future = _dialProfile(profile).whenComplete(
      () => _dialInFlight.remove(profile.id),
    );
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
