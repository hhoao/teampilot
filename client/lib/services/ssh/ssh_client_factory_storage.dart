part of 'ssh_client_factory.dart';

typedef _SshWorkerDialTargetResolver =
    Future<SshWorkerDialTarget> Function(SshProfile profile);

typedef _SshWorkerStorageClosed =
    void Function(
      String profileId,
      SshTransportCloseReason reason,
      StackTrace stackTrace,
    );

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
    final pending = _openings[profile.id];
    if (pending != null && pending.hostIdentifier == profile.hostIdentifier) {
      return pending.future;
    }
    if (pending != null) {
      disconnectProfile(
        profile.id,
        reason: SshTransportCloseReason.hostIdentityChanged,
      );
    }

    final token = Object();
    // Register the opening before `_open` runs: a cached connection can
    // complete synchronously, and `_throwIfOpeningInvalidated` must observe
    // this token as current.
    final completer = Completer<SshWorkerStorageClient>();
    _openings[profile.id] = _WorkerStorageOpening(
      token: token,
      hostIdentifier: profile.hostIdentifier,
      future: completer.future,
    );
    unawaited(() async {
      try {
        completer.complete(
          await _open(
            profile,
            token: token,
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
    required Duration timeout,
    required bool probeCached,
  }) async {
    final cached = _connections[profile.id];
    if (cached != null) {
      if (cached.hostIdentifier == profile.hostIdentifier && !cached.closed) {
        final probeDue =
            cached.lastProbedAt == null ||
            DateTime.now().difference(cached.lastProbedAt!) >= probeInterval;
        // Never probe-evict while another storage operation is in flight; a
        // slow probe would cancel a legitimate long transfer on this lease.
        if (!probeCached || !probeDue || _isBusy(profile.id)) {
          _throwIfOpeningInvalidated(profile.id, token);
          return cached.storage;
        }
        if (await _probe(cached.storage)) {
          cached.lastProbedAt = DateTime.now();
          _throwIfOpeningInvalidated(profile.id, token);
          return cached.storage;
        }
        _retireConnection(
          profile.id,
          cached,
          reason: SshTransportCloseReason.transportError,
        );
      } else {
        _retireConnection(
          profile.id,
          cached,
          reason: SshTransportCloseReason.hostIdentityChanged,
          shutdownWorker: true,
        );
      }
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
              reason: SshTransportCloseReason.transportError,
            );
          }
        },
      ),
      requestTimeout: timeout,
    );
    connection = _WorkerStorageConnection(
      lease: lease,
      storage: storage,
      hostIdentifier: profile.hostIdentifier,
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

  Future<bool> _probe(SshWorkerStorageClient storage) async {
    // A single slow SFTP round trip is common on mobile links during a radio
    // wake-up or a network handover. Retiring the lease on that one blip tears
    // down every session plane and forces a full relaunch, so confirm with a
    // second probe before declaring the transport dead.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // Probe the SFTP plane itself. A shell `exec` probe rejects valid
        // SFTP-only accounts and adds a full exec-channel round trip.
        await storage.realpath('.', timeout: SshStorageIo.probeTimeout);
        return true;
      } on Object {
        // Retry once below.
      }
    }
    return false;
  }

  void disconnectProfile(
    String profileId, {
    required SshTransportCloseReason reason,
  }) {
    _openings.remove(profileId);
    final connection = _connections[profileId];
    if (connection != null) {
      _retireConnection(
        profileId,
        connection,
        reason: reason,
        shutdownWorker: true,
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
    final connection = _connections[profileId];
    if (connection != null) {
      _retireConnection(profileId, connection, reason: reason);
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
      _onPoolChanged(profileId);
      if (notifyTransportClose) {
        _onTransportClosed(profileId, reason, StackTrace.current);
      }
    }
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
    required this.hostIdentifier,
    required this.future,
  });

  final Object token;
  final String hostIdentifier;
  final Future<SshWorkerStorageClient> future;
}

final class _WorkerStorageConnection {
  _WorkerStorageConnection({
    required this.lease,
    required this.storage,
    required this.hostIdentifier,
  });

  final SshProfileWorkerLease lease;
  final SshWorkerStorageClient storage;
  final String hostIdentifier;
  StreamSubscription<SshWorkerEvent>? eventsSubscription;
  DateTime? lastProbedAt;
  var readyCompleted = false;
  var closed = false;
}
