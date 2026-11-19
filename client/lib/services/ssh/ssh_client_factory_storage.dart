part of 'ssh_client_factory.dart';

typedef _SshWorkerDialTargetResolver =
    Future<SshWorkerDialTarget> Function(SshProfile profile);

typedef _SshWorkerStorageClosed =
    void Function(
      String profileId,
      SshTransportCloseReason reason,
      StackTrace stackTrace,
    );

/// Outcome of a keepalive probe. A [timedOut] probe means the link is slow
/// (radio wake-up / handover), not necessarily dead; only [dead] is proof.
enum _ProbeOutcome { healthy, timedOut, dead }

/// Owns the factory's production storage leases without exposing dartssh2
/// clients across the worker boundary.
final class _SshWorkerStoragePool {
  _SshWorkerStoragePool({
    required SshProfileWorkerManager manager,
    required this.probeInterval,
    required _SshWorkerDialTargetResolver resolveDialTarget,
    required Future<void> Function(String profileId) waitForDrain,
    required bool Function(String profileId) isBusy,
    required void Function(String profileId) onPoolChanged,
    required _SshWorkerStorageClosed onTransportClosed,
  }) : _manager = manager,
       _resolveDialTarget = resolveDialTarget,
       _waitForDrain = waitForDrain,
       _isBusy = isBusy,
       _onPoolChanged = onPoolChanged,
       _onTransportClosed = onTransportClosed;

  final SshProfileWorkerManager _manager;
  final Duration probeInterval;
  final _SshWorkerDialTargetResolver _resolveDialTarget;
  final Future<void> Function(String profileId) _waitForDrain;
  final bool Function(String profileId) _isBusy;
  final void Function(String profileId) _onPoolChanged;
  final _SshWorkerStorageClosed _onTransportClosed;
  final Map<String, _WorkerStorageConnection> _connections = {};
  final Map<String, _WorkerStorageOpening> _openings = {};

  /// After a live storage plane is retired, the next reopen waits out this
  /// window. Without it every consumer (acp-history, shared-state, favourites,
  /// display prefs, marketplace sweep…) reopens at once, so a flaky link turns
  /// into a retire/reopen storm. Concurrent callers coalesce onto the one
  /// delayed opening.
  static const _retireCooldown = Duration(seconds: 2);
  final Map<String, DateTime> _retireCooldowns = {};

  bool hasLiveClient(String profileId) {
    final connection = _connections[profileId];
    return connection != null &&
        connection.readyCompleted &&
        !connection.closed;
  }

  Future<SshWorkerStorageClient> clientFor(
    SshProfile profile, {
    required Duration timeout,
    required bool probeCached,
  }) {
    final generation = planGenerationOf(profile);
    final pending = _openings[profile.id];
    if (pending != null) {
      if (pending.generation == generation) return pending.future;
      // The pending dial belongs to a superseded plan. Drop it: its opener will
      // see the token is no longer current and retry under the new plan.
      _openings.remove(profile.id);
      _retireForPlanChange(profile.id);
    }

    final token = Object();
    // Register the opening before `_open` runs: a cached connection can
    // complete synchronously, and `_throwIfOpeningInvalidated` must observe
    // this token as current.
    final completer = Completer<SshWorkerStorageClient>();
    _openings[profile.id] = _WorkerStorageOpening(
      token: token,
      generation: generation,
      future: completer.future,
    );
    unawaited(() async {
      try {
        completer.complete(
          await _open(
            profile,
            token: token,
            generation: generation,
            timeout: timeout,
            probeCached: probeCached,
          ),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future.whenComplete(() {
      final current = _openings[profile.id];
      if (current != null && identical(current.token, token)) {
        _openings.remove(profile.id);
      }
    });
  }

  Future<SshWorkerStorageClient> _open(
    SshProfile profile, {
    required Object token,
    required int generation,
    required Duration timeout,
    required bool probeCached,
  }) async {
    final cached = _connections[profile.id];
    if (cached != null) {
      if (cached.generation == generation && !cached.closed) {
        final probeDue =
            cached.lastProbedAt == null ||
            DateTime.now().difference(cached.lastProbedAt!) >= probeInterval;
        // Never probe-evict while another storage operation is in flight; a
        // slow probe would cancel a legitimate long transfer on this lease.
        if (!probeCached || !probeDue || _isBusy(profile.id)) {
          _throwIfOpeningInvalidated(profile.id, token);
          return cached.storage;
        }
        final probe = await _probe(cached.storage);
        if (probe == _ProbeOutcome.healthy) {
          cached.probeTimeouts = 0;
          cached.lastProbedAt = DateTime.now();
          _throwIfOpeningInvalidated(profile.id, token);
          return cached.storage;
        }
        if (probe == _ProbeOutcome.timedOut && cached.probeTimeouts < 1) {
          // A single slow round trip (radio wake-up / handover) is common on
          // mobile links. Retiring the lease here tears down every storage
          // reader and forces a full reconnect; keep it and let the next real
          // request (or a confirmed second timeout) decide.
          cached.probeTimeouts += 1;
          cached.lastProbedAt = DateTime.now();
          _throwIfOpeningInvalidated(profile.id, token);
          return cached.storage;
        }
        _retireConnection(
          profile.id,
          cached,
          reason: SshTransportCloseReason.transportError,
        );
      } else if (!cached.closed) {
        // The dial plan changed. This is local intent, not a transport
        // failure: retire the old lease, keep the worker (member planes stay
        // up) and start no cooldown, so the caller re-dials immediately.
        _retireForPlanChange(profile.id);
      }
    }

    // Space reopens after a recent retirement so a flaky link does not turn
    // every consumer into a dial at once. Concurrent callers coalesce on this
    // single opening, so only one waits.
    final cooldownUntil = _retireCooldowns[profile.id];
    if (cooldownUntil != null) {
      final remaining = cooldownUntil.difference(DateTime.now());
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
        _throwIfOpeningInvalidated(profile.id, token);
      }
      _retireCooldowns.remove(profile.id);
    }

    final lease = await _manager.acquire(profile);
    if (!_isCurrentOpening(profile.id, token)) {
      await lease.release();
      throw StateError('SSH worker storage opening was invalidated');
    }

    late final _WorkerStorageConnection connection;
    final storage = SshWorkerStorageClient(
      SshWorkerLeaseStorageTransport(
        lease,
        requestTimeout: timeout,
        onTimeout: () {
          if (identical(_connections[profile.id], connection)) {
            _retireConnection(
              profile.id,
              connection,
              reason: SshTransportCloseReason.commandTimeout,
            );
          }
        },
      ),
      requestTimeout: timeout,
    );
    connection = _WorkerStorageConnection(
      lease: lease,
      storage: storage,
      generation: generation,
    );
    _connections[profile.id] = connection;
    connection.eventsSubscription = lease.events.listen(
      (event) => _onWorkerEvent(profile.id, connection, event),
      onDone: () {
        if (identical(_connections[profile.id], connection)) {
          _retireConnection(
            profile.id,
            connection,
            reason: SshTransportCloseReason.transportError,
          );
        }
      },
    );
    try {
      final target = await _resolveDialTarget(profile);
      _throwIfConnectionInvalidated(profile.id, token, connection);
      await storage.connect(profile, target, timeout: timeout);
      _throwIfConnectionInvalidated(profile.id, token, connection);
      connection.lastProbedAt = DateTime.now();
      connection.readyCompleted = true;
      _retireCooldowns.remove(profile.id);
      _onPoolChanged(profile.id);
      return storage;
    } on Object {
      if (identical(_connections[profile.id], connection)) {
        _retireConnection(
          profile.id,
          connection,
          reason: SshTransportCloseReason.authFailed,
        );
      }
      rethrow;
    }
  }

  Future<_ProbeOutcome> _probe(SshWorkerStorageClient storage) async {
    // A single slow SFTP round trip is common on mobile links during a radio
    // wake-up or a network handover. Retry once; if both attempts fail, a pure
    // timeout means "slow" (tolerable) while any definitive transport error
    // means "dead".
    var timedOut = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // Probe the SFTP plane itself. A shell `exec` probe rejects valid
        // SFTP-only accounts and adds a full exec-channel round trip.
        await storage.realpath('.', timeout: SshStorageIo.probeTimeout);
        return _ProbeOutcome.healthy;
      } on TimeoutException {
        timedOut = true;
      } on Object {
        // Definitive error; still retry once below before giving up.
      }
    }
    return timedOut ? _ProbeOutcome.timedOut : _ProbeOutcome.dead;
  }

  void disconnectProfile(
    String profileId, {
    required SshTransportCloseReason reason,
  }) {
    _openings.remove(profileId);
    _retireCooldowns.remove(profileId);
    final connection = _connections[profileId];
    if (connection != null) {
      _retireConnection(
        profileId,
        connection,
        reason: reason,
        shutdownWorker: true,
        cooldown: false,
      );
      return;
    }
    _disconnectManagerAfterDrain(profileId);
  }

  /// Closes the storage plane without stopping member/PTY/forward leases.
  void disconnectStorage(
    String profileId, {
    required SshTransportCloseReason reason,
  }) {
    _openings.remove(profileId);
    _retireCooldowns.remove(profileId);
    final connection = _connections[profileId];
    if (connection != null) {
      _retireConnection(profileId, connection, reason: reason, cooldown: false);
    }
  }

  void disconnectAll({required SshTransportCloseReason reason}) {
    final profileIds = <String>{..._connections.keys, ..._openings.keys};
    for (final profileId in profileIds) {
      disconnectProfile(profileId, reason: reason);
    }
  }

  void _onWorkerEvent(
    String profileId,
    _WorkerStorageConnection connection,
    SshWorkerEvent event,
  ) {
    if (event.kind != SshWorkerEventKind.transportClose ||
        event.plane != SshTransportPlane.storage ||
        !identical(_connections[profileId], connection)) {
      return;
    }
    final reason = event.reason ?? SshTransportCloseReason.transportError;
    _retireConnection(
      profileId,
      connection,
      reason: reason,
      notifyTransportClose: false,
    );
  }

  void _retireConnection(
    String profileId,
    _WorkerStorageConnection connection, {
    required SshTransportCloseReason reason,
    bool notifyTransportClose = true,
    bool shutdownWorker = false,
    bool cooldown = true,
  }) {
    if (!identical(_connections[profileId], connection)) return;
    _connections.remove(profileId);
    connection.closed = true;
    _ignoreErrors(connection.eventsSubscription?.cancel());
    // Storage failures are plane-scoped: close only the SFTP/exec connection
    // owned by the worker's storage core. Other leases (terminals, members,
    // reverse tunnels) must survive a single slow or failed file operation.
    _ignoreErrors(_disconnectStoragePlane(connection));
    _ignoreErrors(connection.lease.release());
    if (shutdownWorker) _disconnectManagerAfterDrain(profileId);
    if (connection.readyCompleted) {
      // An unexpected retire (probe / timeout / transport event) backs the next
      // reopen off; a deliberate disconnect (user / retarget) does not.
      if (cooldown) {
        _retireCooldowns[profileId] = DateTime.now().add(_retireCooldown);
      }
      _onPoolChanged(profileId);
      if (notifyTransportClose) {
        _onTransportClosed(profileId, reason, StackTrace.current);
      }
    }
  }

  /// Retires the live lease because its plan was superseded.
  ///
  /// Deliberately silent: no transport-close event, because this is local
  /// intent and must not trip the shared I/O breaker. The worker is recycled
  /// because one worker owns one SSH connection: an address, account or trust
  /// change invalidates every plane riding it, so member/PTY sessions cannot
  /// survive that change. A last-good endpoint switch never reaches here — it
  /// leaves the address set (and therefore the generation) untouched.
  void _retireForPlanChange(String profileId) {
    final connection = _connections[profileId];
    if (connection == null) return;
    _retireConnection(
      profileId,
      connection,
      reason: SshTransportCloseReason.profileInvalidated,
      notifyTransportClose: false,
      shutdownWorker: true,
      cooldown: false,
    );
  }

  Future<void> _disconnectStoragePlane(
    _WorkerStorageConnection connection,
  ) async {
    try {
      await connection.lease.send(
        SshWorkerRequest(
          requestId: connection.lease.resourceId('storage-disconnect'),
          operation: SshWorkerOperation.disconnectStorage,
        ),
      );
    } on Object {
      // The worker may already be gone; lease release below still bounds it.
    }
  }

  void _disconnectManagerAfterDrain(String profileId) {
    _ignoreErrors(
      _manager.disconnectProfile(
        profileId,
        afterDrain: _waitForDrain(profileId),
      ),
    );
  }

  bool _isCurrentOpening(String profileId, Object token) {
    final current = _openings[profileId];
    return current != null && identical(current.token, token);
  }

  void _throwIfOpeningInvalidated(String profileId, Object token) {
    if (!_isCurrentOpening(profileId, token)) {
      throw StateError('SSH worker storage opening was invalidated');
    }
  }

  void _throwIfConnectionInvalidated(
    String profileId,
    Object token,
    _WorkerStorageConnection connection,
  ) {
    _throwIfOpeningInvalidated(profileId, token);
    if (connection.closed || !identical(_connections[profileId], connection)) {
      throw StateError('SSH worker storage connection was invalidated');
    }
  }

  void _ignoreErrors(Future<void>? future) {
    if (future == null) return;
    unawaited(future.catchError((_) {}));
  }
}

final class _WorkerStorageOpening {
  const _WorkerStorageOpening({
    required this.token,
    required this.generation,
    required this.future,
  });

  final Object token;
  final int generation;
  final Future<SshWorkerStorageClient> future;
}

final class _WorkerStorageConnection {
  _WorkerStorageConnection({
    required this.lease,
    required this.storage,
    required this.generation,
  });

  final SshProfileWorkerLease lease;
  final SshWorkerStorageClient storage;

  /// Content generation of the dial plan this lease was opened under.
  final int generation;
  StreamSubscription<SshWorkerEvent>? eventsSubscription;
  DateTime? lastProbedAt;
  var readyCompleted = false;
  var closed = false;

  /// Consecutive slow (timed-out) probes. One is tolerated; a second confirms
  /// the link is not merely slow. Reset by any healthy probe.
  var probeTimeouts = 0;
}
