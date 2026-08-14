import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import '../remote/remote_connection_monitor.dart';
import 'ssh_client_factory.dart';
import 'ssh_connection_events.dart';
import 'ssh_profile_reconnect_policy.dart';
import 'ssh_transport_close.dart';
import 'ssh_transport_close_policy.dart';

typedef SshProfileResolver = SshProfile? Function(String profileId);

typedef SshSessionPlaneReconnectHandler = Future<void> Function(
  String profileId,
);

typedef SshProfileDisconnectHandler =
    void Function(String profileId, Object error, StackTrace stackTrace);

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
    this.onDisconnect,
    this.onReconnectSessionPlane,
    this.policy = const SshProfileReconnectPolicy(),
  }) : _factory = factory,
       _profileResolver = profileResolver {
    events.onTransportClosed = _onTransportClosed;
    events.onKeepAliveFailed = _onKeepAliveFailed;
    _poolChangesSubscription = _factory.storagePoolChanges.listen(
      _onStoragePoolChanged,
    );
  }

  final SshClientFactory _factory;
  final SshProfileResolver _profileResolver;
  final SshProfileReconnectPolicy policy;
  final SshProfileDisconnectHandler? onDisconnect;
  final SshSessionPlaneReconnectHandler? onReconnectSessionPlane;

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
  Stream<String> get sessionReconnectSignals =>
      _sessionReconnectSignals.stream;

  RemoteConnectionMonitor monitorFor(String profileId) =>
      _monitors.putIfAbsent(profileId, RemoteConnectionMonitor.new);

  Stream<RemoteConnectionState> changesFor(String profileId) =>
      monitorFor(profileId).changes;

  bool isUserDisconnectLatched(String profileId) =>
      _userDisconnectLatched.contains(profileId);

  /// User-initiated durable connect: opens the storage pool and tracks liveness.
  Future<void> userConnect(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _userDisconnectLatched.remove(profile.id);
    await _factory.clientForStorage(profile, timeout: timeout);
    monitorFor(profile.id);
  }

  /// User-initiated disconnect: suppress auto-reconnect until the pool is live again.
  Future<void> userDisconnect(String profileId) async {
    _userDisconnectLatched.add(profileId);
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

  void _onStoragePoolChanged(String profileId) {
    if (!_factory.hasLiveStorageClient(profileId)) return;
    // Auto-reconnect must not clear the user-disconnect latch; only deliberate
    // pool opens (userConnect / external clientForStorage) do.
    if (_userDisconnectLatched.contains(profileId) &&
        _reconnectInFlight[profileId] == true) {
      return;
    }
    _userDisconnectLatched.remove(profileId);
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
      }
      return;
    }
    _scheduleReconnect(profileId);
  }

  bool _shouldSkipReconnect(Object error) {
    if (error is SSHHostkeyError) return true;
    if (error is SSHAuthAbortError && error.reason is SSHHostkeyError) {
      return true;
    }
    return false;
  }

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

  void _scheduleReconnect(String profileId) {
    if (_disposed ||
        _reconnectInFlight[profileId] == true ||
        _userDisconnectLatched.contains(profileId)) {
      return;
    }
    final profile = _profileResolver(profileId);
    if (profile == null) return;

    final attempts = _reconnectAttempts[profileId] ?? 0;
    if (attempts >= policy.maxAttempts) {
      appLogger.w(
        '[ssh] profile $profileId reconnect gave up after $attempts attempts',
      );
      return;
    }

    _reconnectTimers[profileId]?.cancel();
    _reconnectTimers[profileId] = Timer(policy.delayForAttempt(attempts), () {
      unawaited(_runReconnect(profile));
    });
  }

  Future<void> _runReconnect(SshProfile profile) async {
    if (_disposed) return;
    final profileId = profile.id;
    if (_reconnectInFlight[profileId] == true) return;
    if (_userDisconnectLatched.contains(profileId)) return;
    if (monitorFor(profileId).state.isHealthy) return;

    _reconnectInFlight[profileId] = true;
    _reconnectAttempts[profileId] = (_reconnectAttempts[profileId] ?? 0) + 1;
    final attempt = _reconnectAttempts[profileId]!;

    final monitor = monitorFor(profileId);
    monitor.reconnectStarted();
    appLogger.i(
      '[ssh] profile $profileId reconnect attempt $attempt/${policy.maxAttempts}',
    );

    try {
      await reconnectStorage(profile);
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
    } on Object catch (error, stackTrace) {
      if (_userDisconnectLatched.contains(profileId)) {
        monitor.reconnectFailed();
        return;
      }
      monitor.reconnectFailed();
      appLogger.w(
        '[ssh] profile $profileId reconnect failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      if (!_shouldSkipReconnect(error)) {
        _scheduleReconnect(profileId);
      }
    } finally {
      _reconnectInFlight[profileId] = false;
    }
  }

  /// Re-establish the pooled storage client for [profile]. Concurrent callers
  /// share one in-flight attempt.
  Future<void> reconnectStorage(
    SshProfile profile, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final existing = _storageReconnects[profile.id];
    if (existing != null) return existing;

    final attempt = _factory
        .clientForStorage(profile, timeout: timeout)
        .then((_) {})
        .whenComplete(() {
          _storageReconnects.remove(profile.id);
        });
    _storageReconnects[profile.id] = attempt;
    return attempt;
  }

  Future<void> dispose() async {
    _disposed = true;
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
    _pendingDisconnectErrors.clear();
    _pendingDisconnectStacks.clear();
    _pendingScheduleStorageReconnect.clear();
    _pendingEmitDisconnectNotification.clear();
    _storageReconnects.clear();
    if (!_sessionReconnectSignals.isClosed) {
      await _sessionReconnectSignals.close();
    }
    for (final monitor in _monitors.values) {
      await monitor.dispose();
    }
    _monitors.clear();
  }
}
