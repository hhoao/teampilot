import 'dart:async';

import '../../../models/ssh_profile.dart';
import '../../../utils/logging/logger.dart';
import 'ssh_profile_worker_client.dart';
import 'ssh_worker_entry.dart';
import 'ssh_worker_metrics.dart';
import 'ssh_worker_protocol.dart';

/// Owns reusable, profile-scoped SSH worker generations and their leases.
class SshProfileWorkerManager {
  SshProfileWorkerManager({
    SshWorkerLauncher? launcher,
    SshWorkerAuthChallengeHandler? Function(SshProfile profile)?
    authChallengeHandlerFor,
    SshWorkerMetrics? metrics,
    this.idleTimeout = const Duration(minutes: 1),
  }) : _launcher = launcher ?? const IsolateSshWorkerLauncher(),
       _authChallengeHandlerFor = authChallengeHandlerFor,
       _metrics = metrics;

  final SshWorkerLauncher _launcher;
  final SshWorkerAuthChallengeHandler? Function(SshProfile profile)?
  _authChallengeHandlerFor;
  final SshWorkerMetrics? _metrics;
  final Duration idleTimeout;
  final Map<String, _WorkerRecord> _workers = {};
  final Map<String, int> _generations = {};
  final StreamController<SshProfileWorkerManagerEvent> _events =
      StreamController<SshProfileWorkerManagerEvent>.broadcast();
  var _closed = false;
  Future<void>? _closeFuture;

  /// Lifecycle events from the latest profile generation only.
  ///
  /// The manager event controller is asynchronous. An event can therefore be
  /// accepted while a generation is active and delivered after that
  /// generation has been disconnected. Filter at the public stream boundary
  /// so queued envelopes are checked against the generation that is active at
  /// consumption time, not only when they are enqueued. An event accepted
  /// before an explicit disconnect remains relevant until a newer generation
  /// is created, so the normal close notification is not lost during teardown.
  Stream<SshProfileWorkerManagerEvent> get events =>
      _events.stream.where(_isLatestEvent);

  /// Creates an independent manager with the same worker launcher.
  ///
  /// Connectivity probes use this to keep their temporary credentials and
  /// worker lifecycle separate from the profile's durable worker generation.
  SshProfileWorkerManager detached({
    SshWorkerAuthChallengeHandler? Function(SshProfile profile)?
    authChallengeHandlerFor,
  }) => SshProfileWorkerManager(
    launcher: _launcher,
    authChallengeHandlerFor: authChallengeHandlerFor,
    metrics: _metrics,
    idleTimeout: idleTimeout,
  );

  /// Whether [generation] is still the latest generation token for [profileId].
  ///
  /// Consumers that receive an already-queued envelope can use this as a
  /// final synchronous guard before propagating a lifecycle event. The token
  /// remains current after disconnect until the next acquire, which preserves
  /// a close event that was already accepted before teardown.
  bool isCurrentGeneration(String profileId, int generation) =>
      _generations[profileId] == generation;

  /// Acquires one lease on the current worker generation for [profile].
  Future<SshProfileWorkerLease> acquire(SshProfile profile) async {
    if (_closed) throw StateError('SSH profile worker manager is closed');
    final existing = _workers[profile.id];
    if (existing != null) return _acquireRecord(profile.id, existing);

    final generation = (_generations[profile.id] ?? 0) + 1;
    _generations[profile.id] = generation;
    final record = _WorkerRecord(
      profileId: profile.id,
      generation: generation,
      client: _createClient(profile, generation),
    );
    _workers[profile.id] = record;
    try {
      return await _acquireRecord(profile.id, record);
    } on Object {
      if (identical(_workers[profile.id], record)) {
        _workers.remove(profile.id);
      }
      rethrow;
    }
  }

  /// Explicitly stops the active worker for one disconnected profile.
  Future<void> disconnectProfile(
    String profileId, {
    Future<void>? afterDrain,
  }) async {
    final record = _workers.remove(profileId);
    if (record == null) return;
    try {
      if (afterDrain != null) await afterDrain;
    } finally {
      await _shutdown(record);
    }
  }

  /// Forces every currently idle worker through its normal shutdown path.
  Future<void> flushIdleShutdowns() async {
    final idle = _workers.entries
        .where((entry) => entry.value.leases == 0)
        .toList(growable: false);
    for (final entry in idle) {
      if (identical(_workers[entry.key], entry.value)) {
        _workers.remove(entry.key);
        await _shutdown(entry.value);
      }
    }
  }

  /// Stops all current worker generations and prevents further acquisitions.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    final workers = _workers.entries.toList(growable: false);
    _workers.clear();
    for (final entry in workers) {
      await _shutdown(entry.value);
    }
    await _events.close();
  }

  Future<SshProfileWorkerClient> _createClient(
    SshProfile profile,
    int generation,
  ) async {
    final launch = await _launcher.spawn(
      profile: profile,
      generation: generation,
      debugName: 'ssh-profile-worker:${profile.id}',
    );
    final client = SshProfileWorkerClient(
      profileId: profile.id,
      generation: generation,
      launch: launch,
      onAuthChallenge: _authChallengeHandlerFor?.call(profile),
      metrics: _metrics,
    );
    final context = _metricContext(profile.id, generation);
    _metrics?.workerStarted(context);
    _metrics?.emitSnapshot(context);
    return client;
  }

  Future<SshProfileWorkerLease> _acquireRecord(
    String profileId,
    _WorkerRecord record,
  ) async {
    if (record.shuttingDown) {
      throw StateError('SSH profile worker is shutting down');
    }
    record.idleTimer?.cancel();
    record.idleTimer = null;
    final client = await record.client;
    if (record.shuttingDown) {
      throw StateError('SSH profile worker is shutting down');
    }
    _watchEvents(profileId, record, client);
    record.leases++;
    return SshProfileWorkerLease._(this, profileId, record, client);
  }

  void _watchEvents(
    String profileId,
    _WorkerRecord record,
    SshProfileWorkerClient client,
  ) {
    if (record.eventsSubscription != null) return;
    record.eventsSubscription = client.events.listen(
      (event) {
        if (_closed ||
            record.shuttingDown ||
            !identical(_workers[profileId], record) ||
            _events.isClosed) {
          return;
        }
        _events.add(
          SshProfileWorkerManagerEvent(
            profileId: profileId,
            generation: client.generation,
            event: event,
          ),
        );
      },
      onDone: () {
        if (record.shuttingDown || !identical(_workers[profileId], record)) {
          return;
        }
        _workers.remove(profileId);
        unawaited(_shutdown(record));
      },
    );
  }

  bool _isLatestEvent(SshProfileWorkerManagerEvent envelope) =>
      isCurrentGeneration(envelope.profileId, envelope.generation);

  Future<void> _release(String profileId, _WorkerRecord record) async {
    if (record.leases == 0) return;
    record.leases--;
    if (record.leases != 0 || record.shuttingDown) return;
    record.idleTimer?.cancel();
    record.idleTimer = Timer(idleTimeout, () {
      if (record.leases != 0 || !identical(_workers[profileId], record)) {
        return;
      }
      _workers.remove(profileId);
      unawaited(_shutdown(record));
    });
  }

  Future<void> _shutdown(_WorkerRecord record) {
    if (record.shutdown != null) return record.shutdown!;
    record.shuttingDown = true;
    record.idleTimer?.cancel();
    record.idleTimer = null;
    return record.shutdown = _shutdownRecord(record);
  }

  Future<void> _shutdownRecord(_WorkerRecord record) async {
    final context = _metricContext(record.profileId, record.generation);
    final metrics = _metrics;
    metrics?.workerShutdownStarted(context, metrics.now());
    try {
      await record.eventsSubscription?.cancel();
      record.eventsSubscription = null;
      await (await record.client).close();
    } on Object catch (error, stackTrace) {
      // The worker is already gone; shutdown failures must not surface as
      // unhandled zone errors from idle/onDone shutdown paths.
      appLogger.w(
        '[ssh-worker] shutdown failed profile=${record.profileId} '
        'generation=${record.generation}',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (metrics != null) {
        metrics.workerGenerationClosed(context);
        metrics.workerShutdownCompleted(context, metrics.now());
        metrics.emitSnapshot(context);
      }
    }
  }

  SshWorkerMetricContext _metricContext(String profileId, int generation) =>
      SshWorkerMetricContext(profileId: profileId, generation: generation);
}

/// A worker event paired with its profile and generation.
final class SshProfileWorkerManagerEvent {
  const SshProfileWorkerManagerEvent({
    required this.profileId,
    required this.generation,
    required this.event,
  });

  final String profileId;
  final int generation;
  final SshWorkerEvent event;
}

/// A reference-counted view of one profile worker generation.
class SshProfileWorkerLease {
  SshProfileWorkerLease._(
    this._manager,
    this._profileId,
    this._record,
    this._client,
  );

  final SshProfileWorkerManager _manager;
  final String _profileId;
  final _WorkerRecord _record;
  final SshProfileWorkerClient _client;
  var _released = false;

  Object get workerIdentity => _client.workerIdentity;
  int get generation => _client.generation;
  Stream<SshWorkerEvent> get events => _client.events;
  Set<String> get pendingRequestIds => _client.pendingRequestIds;

  String resourceId(String prefix) => _client.resourceId(prefix);

  /// Sends a request through the leased worker generation.
  Future<SshWorkerReply> send(SshWorkerRequest request) {
    if (_record.shuttingDown) {
      return Future<SshWorkerReply>.error(
        StateError('SSH profile worker is shutting down'),
      );
    }
    return _client.send(request);
  }

  /// Releases this lease. Releasing twice is harmless.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _manager._release(_profileId, _record);
  }
}

class _WorkerRecord {
  _WorkerRecord({
    required this.profileId,
    required this.generation,
    required this.client,
  });

  final String profileId;
  final int generation;
  final Future<SshProfileWorkerClient> client;
  var leases = 0;
  var shuttingDown = false;
  Timer? idleTimer;
  Future<void>? shutdown;
  StreamSubscription<SshWorkerEvent>? eventsSubscription;
}
