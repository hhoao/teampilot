import 'dart:async';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../remote/remote_connection_monitor.dart';
import 'ssh_client_factory.dart';
import 'ssh_connection_events.dart';
import 'ssh_connection_failure.dart';
import 'ssh_connection_gate.dart';
import 'ssh_profile_reconnect_policy.dart';
import 'ssh_transport_close.dart';
import 'ssh_transport_close_policy.dart';

typedef SshProfileResolver = SshProfile? Function(String profileId);

typedef SshSessionPlaneReconnectHandler =
    Future<void> Function(String profileId);

typedef SshProfileDisconnectHandler =
    void Function(String profileId, Object error, StackTrace stackTrace);

/// Notified with the profile id and the 1-based attempt number when a
/// reconnect attempt starts.
typedef SshReconnectAttemptHandler =
    void Function(String profileId, int attempt);

/// Notified when a reconnect attempt brought [profileId] back.
typedef SshReconnectedHandler = void Function(String profileId);

/// Decides whether [profileId] must keep retrying past the policy's
/// [SshProfileReconnectPolicy.maxAttempts] instead of giving up.
typedef SshPersistRetryPredicate = bool Function(String profileId);

/// Fired when a permanent, non-retryable close (changed host identity / bad
/// credentials) stops the loop, so the UI can surface it instead of leaving a
/// stale `connected` state behind.
typedef SshNonRetryableCloseHandler =
    void Function(String profileId, Object error);

/// Per-profile SSH liveness, disconnect coalescing, and serialized reconnect.
///
/// One network blip can drop several TCP connections (storage pool + member
/// session planes). This coordinator collapses those into a single down/retry
/// signal per [SshProfile.id].
class SshProfileConnectionCoordinator {
  SshProfileConnectionCoordinator({
    required SshClientFactory factory,
    required SshConnectionEvents events,
    required SshProfileResolver profileResolver,
    SshConnectionGate? gate,
    Future<void> Function(SshProfile profile)? dial,
    this.onDisconnect,
    this.onReconnectSessionPlane,
    this.onReconnectAttempt,
    this.onReconnected,
    this.onNonRetryableClose,
    this.persistRetry,
    this.policy = const SshProfileReconnectPolicy(),
  }) : _factory = factory,
       _gate = gate ?? factory.connectionGate,
       _dial = dial ??
           ((profile) => factory.ensureStorageConnected(
             profile,
             allowDialWhenDown: true,
           )),
       _profileResolver = profileResolver {
    events.onTransportClosed = _onTransportClosed;
    events.onKeepAliveFailed = _onKeepAliveFailed;
    _gate.onWaiter = _onGateWaiter;
    _gate.onDown = _onGateDown;
    _poolChangesSubscription = _factory.storagePoolChanges.listen(
      _onStoragePoolChanged,
    );
  }

  final SshClientFactory _factory;
  final SshConnectionGate _gate;
  final Future<void> Function(SshProfile profile) _dial;
  final SshProfileResolver _profileResolver;
  final SshProfileReconnectPolicy policy;
  final SshProfileDisconnectHandler? onDisconnect;
  final SshSessionPlaneReconnectHandler? onReconnectSessionPlane;

  /// Progress surface for a persistent retry loop (the home connection page).
  final SshReconnectAttemptHandler? onReconnectAttempt;

  /// Success surface: fires once per successful attempt, never on failure.
  final SshReconnectedHandler? onReconnected;

  /// Permanent-failure surface for the home connection page.
  final SshNonRetryableCloseHandler? onNonRetryableClose;

  /// When it returns true for a profile, retries continue at
  /// [SshProfileReconnectPolicy.maxDelay] past [SshProfileReconnectPolicy.maxAttempts]
  /// instead of giving up. Other profiles keep the default give-up behavior.
  final SshPersistRetryPredicate? persistRetry;

  final Map<String, RemoteConnectionMonitor> _monitors = {};
  final Map<String, Future<void>> _storageReconnects = {};
  final Map<String, Timer> _disconnectCoalesceTimers = {};
  final Map<String, Object> _pendingDisconnectErrors = {};
  final Map<String, StackTrace> _pendingDisconnectStacks = {};
  final Map<String, bool> _pendingScheduleStorageReconnect = {};
  final Map<String, bool> _pendingEmitDisconnectNotification = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, bool> _reconnectInFlight = {};
  final StreamController<String> _sessionReconnectSignals =
      StreamController<String>.broadcast();
  final Set<String> _userDisconnectLatched = {};
  StreamSubscription<String>? _poolChangesSubscription;

  var _disposed = false;

  /// Fires with a profile id when session-plane reconnect should run (chat
  /// shells, workspace terminals, …).
  Stream<String> get sessionReconnectSignals => _sessionReconnectSignals.stream;

  RemoteConnectionMonitor monitorFor(String profileId) =>
      _monitors.putIfAbsent(profileId, RemoteConnectionMonitor.new);

  Stream<RemoteConnectionState> changesFor(String profileId) =>
      monitorFor(profileId).changes;

  bool isUserDisconnectLatched(String profileId) =>
      _userDisconnectLatched.contains(profileId);

  /// User-initiated durable connect: opens the storage pool and tracks liveness.
  /// The dial itself is owned by the supervisor (single-flight, invariant 1).
  Future<void> userConnect(SshProfile profile) async {
    _userDisconnectLatched.remove(profile.id);
    _gate.resume(profile.id);
    await _dial(profile);
    monitorFor(profile.id);
  }

  /// User-initiated disconnect: suppress auto-reconnect until the pool is live again.
  Future<void> userDisconnect(String profileId) async {
    _userDisconnectLatched.add(profileId);
    _gate.suspend(profileId);
    monitorFor(profileId).markDown();
    _disconnectCoalesceTimers[profileId]?.cancel();
    _disconnectCoalesceTimers.remove(profileId);
    _reconnectTimers[profileId]?.cancel();
    _reconnectTimers.remove(profileId);
    _pendingDisconnectErrors.remove(profileId);
    _pendingDisconnectStacks.remove(profileId);
    _pendingScheduleStorageReconnect.remove(profileId);
    _pendingEmitDisconnectNotification.remove(profileId);
    _factory.disconnectProfile(
      profileId,
      reason: SshTransportCloseReason.userDisconnect,
    );
  }

  /// Clears the spent backoff window for [profileId], cancelling any pending
  /// retry timer. An explicit user retry then starts from attempt 1 again.
  void resetReconnectAttempts(String profileId) {
    _reconnectAttempts.remove(profileId);
    _reconnectTimers.remove(profileId)?.cancel();
  }

  /// Schedules a fresh attempt for [profileId] after the loop stopped (gave up
  /// or was cancelled). Used by an explicit "retry now"; the user-disconnect
  /// latch must be cleared first (see [userConnect]).
  ///
  /// Marks the target down for the connection UI and schedules a fresh
  /// attempt. The gate — not the monitor — decides whether a dial is needed.
  void restartReconnect(String profileId) {
    if (_disposed) return;
    _reconnectAttempts.remove(profileId);
    monitorFor(profileId).markDown();
    _scheduleReconnect(profileId);
  }

  /// Clears the user-disconnect latch and retries [profileId] immediately.
  ///
  /// The connection page's 「继续重试」 hands off here so the coordinator stays
  /// the single retry driver. The supervisor's dial is single-flight per
  /// profile, so this cannot race a concurrent `ensureStorageConnected`
  /// (the old path called `userConnect` in parallel and produced
  /// `Duplicate SSH worker request id`).
  void resumeRetries(String profileId) {
    if (_disposed) return;
    _userDisconnectLatched.remove(profileId);
    _gate.resume(profileId);
    resetReconnectAttempts(profileId);
    final profile = _profileResolver(profileId);
    if (profile == null) return;
    monitorFor(profileId).markDown();
    if (_reconnectInFlight[profileId] == true) {
      _scheduleReconnect(profileId);
      return;
    }
    unawaited(_runReconnect(profile));
  }

  void _onStoragePoolChanged(String profileId) {
    if (!_factory.hasLiveStorageClient(profileId)) return;
    // Auto-reconnect must not clear the user-disconnect latch; only deliberate
    // pool opens (userConnect / external clientForStorage) do.
    if (_userDisconnectLatched.contains(profileId) &&
        _reconnectInFlight[profileId] == true) {
      return;
    }
    _userDisconnectLatched.remove(profileId);
    _gate.resume(profileId);
    _gate.markUp(profileId);
    final monitor = monitorFor(profileId);
    if (monitor.state.status == RemoteConnectionStatus.down) {
      monitor.reconnected();
    }
  }

  void _onTransportClosed(
    String profileId,
    Object error,
    StackTrace stackTrace,
  ) {
    final decision = SshTransportClosePolicy.evaluateError(error);
    if (!decision.affectsDurableHome) {
      appLogger.d(
        '[ssh] profile $profileId ignoring non-durable transport close: $error',
      );
      return;
    }
    // A storage lease can retire on its own (probe failure / request timeout)
    // while the shared SSH client and the forward planes stay healthy. That is
    // plane-scoped: the next storageFor reopens it, and a failed reopen trips
    // the gate. Do not take the whole home down for it.
    if (error is SshTransportClosed &&
        error.plane == SshTransportPlane.storage &&
        !isNonRetryableTransportClose(error)) {
      appLogger.d('[ssh] profile $profileId storage plane retired: $error');
      return;
    }
    _gate.markDown(profileId);
    _enqueueDisconnect(
      profileId,
      error,
      stackTrace,
      markDown: true,
      scheduleStorageReconnect: decision.scheduleStorageReconnect,
      emitDisconnectNotification: decision.emitDisconnectNotification,
    );
  }

  void _onKeepAliveFailed(
    String profileId,
    Object error,
    StackTrace stackTrace,
  ) {
    final monitor = monitorFor(profileId);
    final before = monitor.state;
    monitor.heartbeatTimedOut();
    final after = monitor.state;
    if (after.status == RemoteConnectionStatus.down &&
        before.status != RemoteConnectionStatus.down) {
      _enqueueDisconnect(
        profileId,
        error,
        stackTrace,
        markDown: false,
        scheduleStorageReconnect: true,
        emitDisconnectNotification: true,
      );
      return;
    }
    if (after.status == RemoteConnectionStatus.down) {
      _scheduleReconnect(profileId);
    }
  }

  void _enqueueDisconnect(
    String profileId,
    Object error,
    StackTrace stackTrace, {
    required bool markDown,
    required bool scheduleStorageReconnect,
    required bool emitDisconnectNotification,
  }) {
    if (_disposed) return;
    final previous = _pendingDisconnectErrors[profileId];
    if (previous == null || _shouldPreferDisconnectError(error, previous)) {
      _pendingDisconnectErrors[profileId] = error;
      _pendingDisconnectStacks[profileId] = stackTrace;
    }
    // Once any wave asks for reconnect, keep that intent for the coalesce flush.
    _pendingScheduleStorageReconnect[profileId] =
        (_pendingScheduleStorageReconnect[profileId] ?? false) ||
        scheduleStorageReconnect;
    _pendingEmitDisconnectNotification[profileId] =
        (_pendingEmitDisconnectNotification[profileId] ?? false) ||
        emitDisconnectNotification;
    if (markDown) {
      monitorFor(profileId).markDown();
    }
    _disconnectCoalesceTimers[profileId]?.cancel();
    _disconnectCoalesceTimers[profileId] = Timer(
      policy.disconnectCoalesce,
      () => _flushDisconnect(profileId),
    );
  }

  void _flushDisconnect(String profileId) {
    if (_disposed) return;
    _disconnectCoalesceTimers.remove(profileId)?.cancel();
    final error = _pendingDisconnectErrors.remove(profileId);
    final stackTrace =
        _pendingDisconnectStacks.remove(profileId) ?? StackTrace.empty;
    final scheduleReconnect =
        _pendingScheduleStorageReconnect.remove(profileId) ?? true;
    final emitNotification =
        _pendingEmitDisconnectNotification.remove(profileId) ?? true;
    if (error == null) return;

    if (emitNotification) {
      onDisconnect?.call(profileId, error, stackTrace);
    }
    if (!scheduleReconnect || _shouldSkipReconnect(error)) {
      if (_shouldSkipReconnect(error)) {
        appLogger.w(
          '[ssh] profile $profileId disconnect is not retryable: $error',
        );
        // Drop any timer/attempt window left from an earlier wave and latch the
        // profile: a permanent failure must not keep a persistent loop (or an
        // in-flight attempt that reschedules on failure) alive behind the
        // surface. Only an explicit resume clears the latch.
        resetReconnectAttempts(profileId);
        _userDisconnectLatched.add(profileId);
        _gate.suspend(profileId);
        try {
          onNonRetryableClose?.call(profileId, error);
        } on Object catch (hookError, stackTrace) {
          appLogger.w(
            '[ssh] profile $profileId non-retryable hook failed',
            error: hookError,
            stackTrace: stackTrace,
          );
        }
      }
      return;
    }
    _scheduleReconnect(profileId);
  }

  bool _shouldSkipReconnect(Object error) =>
      isSshHostKeyFailure(error) || isNonRetryableTransportClose(error);

  bool _shouldPreferDisconnectError(Object incoming, Object existing) {
    if (_shouldSkipReconnect(incoming) && !_shouldSkipReconnect(existing)) {
      return true;
    }
    if (_shouldSkipReconnect(existing) && !_shouldSkipReconnect(incoming)) {
      return false;
    }
    final incomingGeneric = isGenericSshTransportClose(incoming);
    final existingGeneric = isGenericSshTransportClose(existing);
    if (!incomingGeneric && existingGeneric) return true;
    if (incomingGeneric && !existingGeneric) return false;
    return true;
  }

  void _onGateDown(String profileId) {
    if (_disposed || _userDisconnectLatched.contains(profileId)) return;
    monitorFor(profileId).markDown();
    if (_reconnectInFlight[profileId] == true ||
        _reconnectTimers.containsKey(profileId)) {
      return;
    }
    _scheduleReconnect(profileId);
  }

  void _onGateWaiter(String profileId) {
    if (_disposed || _userDisconnectLatched.contains(profileId)) return;
    if (_reconnectInFlight[profileId] == true ||
        _reconnectTimers.containsKey(profileId)) {
      return;
    }
    _scheduleReconnect(profileId);
  }

  void _scheduleReconnect(String profileId, {bool penaltyRefusal = false}) {
    if (_disposed ||
        _reconnectInFlight[profileId] == true ||
        _userDisconnectLatched.contains(profileId)) {
      return;
    }
    final profile = _profileResolver(profileId);
    if (profile == null) return;

    final attempts = _reconnectAttempts[profileId] ?? 0;
    final exhausted = attempts >= policy.maxAttempts;
    final persist =
        exhausted &&
        (_persistRetry(profileId) ||
            _gate.hasWaiters(profileId));
    if (exhausted && !persist) {
      appLogger.w(
        '[ssh] profile $profileId reconnect gave up after $attempts attempts',
      );
      return;
    }

    final delay = penaltyRefusal
        ? policy.penaltyBackoff
        : persist
        ? policy.maxDelay
        : policy.delayForAttempt(attempts);
    _reconnectTimers[profileId]?.cancel();
    _reconnectTimers[profileId] = Timer(delay, () {
      unawaited(_runReconnect(profile));
    });
  }

  Future<void> _runReconnect(SshProfile profile) async {
    if (_disposed) return;
    final profileId = profile.id;
    if (_reconnectInFlight[profileId] == true) return;
    if (_userDisconnectLatched.contains(profileId)) return;
    if (_gate.isUp(profileId)) return;

    _reconnectInFlight[profileId] = true;
    _reconnectAttempts[profileId] = (_reconnectAttempts[profileId] ?? 0) + 1;
    final attempt = _reconnectAttempts[profileId]!;

    final monitor = monitorFor(profileId);

    // Rescheduling must happen after the finally block clears the in-flight
    // flag — scheduling while it is still set is a silent no-op. Hook
    // invocations live INSIDE the try/finally so a throwing hook cannot leave
    // `_reconnectInFlight` latched and wedge every later attempt.
    var reschedule = false;
    var reschedulePenalty = false;
    try {
      final persistent = _persistRetry(profileId);
      _notifyReconnectAttempt(profileId, attempt);
      monitor.reconnectStarted();
      appLogger.i(
        '[ssh] profile $profileId reconnect attempt '
        '$attempt${persistent ? '' : '/${policy.maxAttempts}'}',
      );

      await _dial(profile);
      if (_userDisconnectLatched.contains(profileId)) {
        _factory.disconnectProfile(
          profileId,
          reason: SshTransportCloseReason.userDisconnect,
        );
        monitor.reconnectFailed();
        return;
      }
      if (!_sessionReconnectSignals.isClosed) {
        _sessionReconnectSignals.add(profileId);
      }
      final sessionPlane = onReconnectSessionPlane;
      if (sessionPlane != null) {
        await sessionPlane(profileId);
      }
      if (_userDisconnectLatched.contains(profileId)) {
        _factory.disconnectProfile(
          profileId,
          reason: SshTransportCloseReason.userDisconnect,
        );
        monitor.reconnectFailed();
        return;
      }
      monitor.reconnected();
      _reconnectAttempts.remove(profileId);
      appLogger.i('[ssh] profile $profileId reconnect succeeded');
      _notifyReconnected(profileId);
    } on Object catch (error, stackTrace) {
      if (_userDisconnectLatched.contains(profileId)) {
        monitor.reconnectFailed();
        return;
      }
      monitor.reconnectFailed();
      reschedulePenalty = isSshdPenaltyRefusal(error);
      appLogger.w(
        '[ssh] profile $profileId reconnect failed'
        '${reschedulePenalty ? ' (sshd penalty refusal)' : ''}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_shouldSkipReconnect(error)) {
        if (reschedulePenalty) {
          // A penalty refusal is a temporary external condition, not a real
          // failure: don't burn an attempt, and wait out the penalty window.
          _reconnectAttempts.remove(profileId);
        }
        reschedule = true;
      }
    } finally {
      _reconnectInFlight[profileId] = false;
    }
    if (reschedule) {
      _scheduleReconnect(profileId, penaltyRefusal: reschedulePenalty);
    }
  }

  /// Runs a progress hook without letting it fail the reconnect itself.
  void _notifyReconnectAttempt(String profileId, int attempt) {
    try {
      onReconnectAttempt?.call(profileId, attempt);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[ssh] reconnect attempt hook failed: ${error.runtimeType}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Runs a success hook without turning a healthy reconnect into a failure.
  void _notifyReconnected(String profileId) {
    try {
      onReconnected?.call(profileId);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[ssh] reconnect success hook failed: ${error.runtimeType}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Evaluates [persistRetry] without wedging the loop on a throwing hook.
  bool _persistRetry(String profileId) {
    try {
      return persistRetry?.call(profileId) ?? false;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[ssh] persistRetry hook failed: ${error.runtimeType}',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Re-establish the pooled storage client for [profile]. Concurrent callers
  /// share one in-flight attempt. This is the test/compat surface; the retry
  /// loop itself dials through the injected [_dial] (single-flight supervisor).
  Future<void> reconnectStorage(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final existing = _storageReconnects[profile.id];
    if (existing != null) return existing;

    final attempt = _factory
        .ensureStorageConnected(
          profile,
          timeout: timeout,
          allowDialWhenDown: true,
        )
        .whenComplete(() {
          _storageReconnects.remove(profile.id);
        });
    _storageReconnects[profile.id] = attempt;
    return attempt;
  }

  Future<void> dispose() async {
    _disposed = true;
    _gate.onWaiter = null;
    await _poolChangesSubscription?.cancel();
    _poolChangesSubscription = null;
    for (final timer in _disconnectCoalesceTimers.values) {
      timer.cancel();
    }
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _disconnectCoalesceTimers.clear();
    _reconnectTimers.clear();
    _storageReconnects.clear();
    _pendingDisconnectErrors.clear();
    _pendingDisconnectStacks.clear();
    _pendingScheduleStorageReconnect.clear();
    _pendingEmitDisconnectNotification.clear();
    if (!_sessionReconnectSignals.isClosed) {
      await _sessionReconnectSignals.close();
    }
    for (final monitor in _monitors.values) {
      await monitor.dispose();
    }
    _monitors.clear();
  }
}
