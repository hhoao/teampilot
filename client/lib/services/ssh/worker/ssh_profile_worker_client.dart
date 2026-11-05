import 'dart:async';

import '../ssh_transport_close.dart';
import 'ssh_worker_entry.dart';
import 'ssh_worker_metrics.dart';
import 'ssh_worker_protocol.dart';

/// UI-side proxy for one generation of a profile worker.
class SshProfileWorkerClient {
  SshProfileWorkerClient({
    required this.profileId,
    required this.generation,
    required SshWorkerLaunch launch,
    SshWorkerAuthChallengeHandler? onAuthChallenge,
    SshWorkerMetrics? metrics,
    this.shutdownTimeout = const Duration(seconds: 5),
  }) : _launch = launch,
       _onAuthChallenge = onAuthChallenge,
       _metrics = metrics {
    _subscription = _launch.messages.listen(
      _onMessage,
      onDone: _onMessagesDone,
    );
  }

  final String profileId;
  final int generation;
  final Duration shutdownTimeout;
  final SshWorkerLaunch _launch;
  final SshWorkerAuthChallengeHandler? _onAuthChallenge;
  final SshWorkerMetrics? _metrics;
  final Map<String, Completer<SshWorkerReply>> _pending = {};
  final Map<String, _PendingMetric> _pendingMetrics = {};
  final Set<String> _forwardStreamIds = {};
  final Map<String, Set<String>> _forwardChannels = {};
  final Map<String, String> _forwardStreamOwners = {};
  final Map<String, SshWorkerMetricPlane> _activeConnectionIds = {};
  final Map<String, _PendingConnection> _pendingConnections = {};
  final Map<String, String> _pendingConnectionClosures = {};
  final StreamController<SshWorkerEvent> _events =
      StreamController<SshWorkerEvent>.broadcast();
  late final StreamSubscription<Object?> _subscription;

  Future<void>? _closeFuture;
  var _closing = false;
  var _messagesClosed = false;
  var _shutdownRequestSequence = 0;
  var _resourceSequence = 0;

  /// Identity of the underlying isolate or direct actor for reuse checks.
  Object get workerIdentity => _launch.workerIdentity;

  String resourceId(String prefix) =>
      '$prefix-$generation-${_resourceSequence++}';

  /// Worker-originated state, output, and lifecycle events for this generation.
  Stream<SshWorkerEvent> get events => _events.stream;

  /// Request ids still awaiting a reply from this generation.
  Set<String> get pendingRequestIds => Set.unmodifiable(_pending.keys);

  /// Sends one protocol request and completes with the corresponding reply.
  Future<SshWorkerReply> send(SshWorkerRequest request) {
    if (_closing || _messagesClosed) {
      return Future<SshWorkerReply>.error(
        StateError(
          _messagesClosed
              ? 'SSH profile worker message channel is closed'
              : 'SSH profile worker is shutting down',
        ),
      );
    }
    return _send(request);
  }

  /// Stops this generation and rejects subsequent [send] calls immediately.
  Future<void> close() => _closeFuture ??= _close();

  Future<SshWorkerReply> _send(SshWorkerRequest request) {
    if (_pending.containsKey(request.requestId)) {
      return Future<SshWorkerReply>.error(
        StateError('Duplicate SSH worker request id: ${request.requestId}'),
      );
    }
    final completer = Completer<SshWorkerReply>();
    _pending[request.requestId] = completer;
    final connectionId = _connectionId(request);
    final plane = _planeFor(request.operation);
    if (_isConnectionRequest(request.operation) &&
        connectionId != null &&
        plane != null) {
      _pendingConnections[request.requestId] = _PendingConnection(
        id: connectionId,
        plane: plane,
      );
    } else if ((request.operation == SshWorkerOperation.closeForward ||
            request.operation == SshWorkerOperation.closeChannel) &&
        connectionId != null) {
      _pendingConnectionClosures[request.requestId] = connectionId;
    }
    final metrics = _metrics;
    _PendingMetric? pendingMetric;
    if (metrics != null && metrics.enabled) {
      pendingMetric = _PendingMetric(
        operation: request.operation,
        context: _metricContext(request),
        connectionId: _connectionId(request),
        sftpPayloadByteCount:
            request.operation == SshWorkerOperation.writeSftpChunk
            ? request.payload?.length
            : null,
      );
      _pendingMetrics[request.requestId] = pendingMetric;
      final started = metrics.now();
      metrics.requestStarted(
        request.requestId,
        started,
        context: pendingMetric.context,
      );
      if (_isConnectionRequest(request.operation)) {
        pendingMetric.isConnection = true;
        metrics.connectStarted(
          pendingMetric.context,
          started,
          connectionId: pendingMetric.connectionId,
        );
      }
      metrics.pendingMessagesChanged(_pending.length);
    }
    try {
      _launch.commands.send(request.toWire());
    } on Object catch (error, stackTrace) {
      _pending.remove(request.requestId);
      _pendingConnections.remove(request.requestId);
      _pendingConnectionClosures.remove(request.requestId);
      _pendingMetrics.remove(request.requestId);
      if (metrics != null && pendingMetric != null) {
        metrics.requestCompleted(
          request.requestId,
          metrics.now(),
          context: pendingMetric.context,
        );
        if (pendingMetric.isConnection) {
          metrics.connectFailed(
            pendingMetric.context,
            connectionId: pendingMetric.connectionId,
          );
        }
        if (_isForwardOpen(pendingMetric.operation) &&
            pendingMetric.connectionId != null) {
          _removeForward(pendingMetric.connectionId!);
        }
        metrics.pendingMessagesChanged(_pending.length);
      }
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  Future<void> _close() async {
    _closing = true;
    Object? shutdownError;
    StackTrace? shutdownStackTrace;
    try {
      if (!_messagesClosed) {
        await _send(
          SshWorkerRequest(
            requestId: '_shutdown-$generation-${_shutdownRequestSequence++}',
            operation: SshWorkerOperation.shutdown,
          ),
        ).timeout(shutdownTimeout);
      }
    } on Object catch (error, stackTrace) {
      shutdownError = error;
      shutdownStackTrace = stackTrace;
    } finally {
      _failPending(StateError('SSH profile worker closed'));
      await _subscription.cancel();
      await _launch.close();
      await _events.close();
    }
    if (shutdownError != null) {
      Error.throwWithStackTrace(shutdownError, shutdownStackTrace!);
    }
  }

  void _onMessage(Object? wire) {
    if (wire is! Map) return;
    switch (wire['type']) {
      case 'reply':
        final SshWorkerReply reply;
        try {
          reply = SshWorkerReply.fromWire(wire);
        } on FormatException {
          // A malformed reply must not escape into the app zone. Its request
          // keeps its normal timeout so one bad generation cannot wedge the UI.
          return;
        }
        _recordConnectionReply(
          reply,
          _pendingConnections.remove(reply.requestId),
        );
        final closedConnectionId = _pendingConnectionClosures.remove(
          reply.requestId,
        );
        if (closedConnectionId != null &&
            reply.kind == SshWorkerReplyKind.success) {
          _activeConnectionIds.remove(closedConnectionId);
        }
        final completer = _pending.remove(reply.requestId);
        _recordReplyMetrics(reply, _pendingMetrics.remove(reply.requestId));
        completer?.complete(reply);
      case 'event':
        final SshWorkerEvent event;
        try {
          event = SshWorkerEvent.fromWire(wire);
        } on FormatException {
          return;
        }
        _recordEventMetrics(event);
        _events.add(event);
      case 'authChallenge':
        unawaited(_answerAuthChallenge(wire));
    }
  }

  Future<void> _answerAuthChallenge(Object? wire) async {
    SshWorkerAuthChallenge challenge;
    try {
      challenge = SshWorkerAuthChallenge.fromWire(wire);
    } on FormatException {
      return;
    }
    final handler = _onAuthChallenge;
    late SshWorkerAuthReply reply;
    if (_closing ||
        _messagesClosed ||
        handler == null ||
        challenge.profileId != profileId) {
      reply = SshWorkerAuthReply.failure(
        requestId: challenge.requestId,
        errorCode: 'auth_challenge_unavailable',
      );
    } else {
      try {
        reply = await handler(challenge);
      } on Object {
        reply = SshWorkerAuthReply.failure(
          requestId: challenge.requestId,
          errorCode: 'auth_challenge_failed',
        );
      }
    }
    if (reply.requestId != challenge.requestId) {
      reply = SshWorkerAuthReply.failure(
        requestId: challenge.requestId,
        errorCode: 'auth_challenge_mismatched_reply',
      );
    }
    if (_closing || _messagesClosed) return;
    try {
      _launch.commands.send(reply.toWire());
    } on Object {
      // The worker has already closed; its pending auth wait will be failed by
      // its normal shutdown path.
    }
  }

  void _onMessagesDone() {
    _messagesClosed = true;
    final planes = _activeConnectionIds.values
        .where(
          (plane) =>
              plane == SshWorkerMetricPlane.storage ||
              plane == SshWorkerMetricPlane.member,
        )
        .toSet();
    _failPending(StateError('SSH profile worker message channel closed'));
    _activeConnectionIds.clear();
    for (final plane in planes) {
      _events.add(
        SshWorkerEvent.transportClosed(
          plane: plane == SshWorkerMetricPlane.storage
              ? SshTransportPlane.storage
              : SshTransportPlane.member,
          reason: SshTransportCloseReason.transportError,
        ),
      );
    }
    unawaited(_events.close());
  }

  void _failPending(Object error) {
    final pending = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final entry in pending) {
      final pendingMetric = _pendingMetrics.remove(entry.key);
      final metrics = _metrics;
      if (pendingMetric != null && metrics != null) {
        metrics.requestCompleted(
          entry.key,
          metrics.now(),
          context: pendingMetric.context,
        );
        if (pendingMetric.isConnection) {
          metrics.connectFailed(
            pendingMetric.context,
            connectionId: pendingMetric.connectionId,
          );
        }
        if (_isForwardOpen(pendingMetric.operation) &&
            pendingMetric.connectionId != null) {
          _removeForward(pendingMetric.connectionId!);
        }
      }
      final completer = entry.value;
      if (!completer.isCompleted) completer.completeError(error);
    }
    _clearForwardTracking();
    _pendingConnections.clear();
    _pendingConnectionClosures.clear();
    _metrics?.pendingMessagesChanged(_pending.length);
  }

  void _recordConnectionReply(
    SshWorkerReply reply,
    _PendingConnection? pending,
  ) {
    if (pending == null) return;
    if (reply.kind == SshWorkerReplyKind.success) {
      _activeConnectionIds[pending.id] = pending.plane;
    }
  }

  void _recordReplyMetrics(SshWorkerReply reply, _PendingMetric? pending) {
    final metrics = _metrics;
    if (metrics == null || pending == null) return;
    final completed = metrics.now();
    metrics.requestCompleted(
      reply.requestId,
      completed,
      context: pending.context,
    );
    if (pending.isConnection) {
      if (reply.kind == SshWorkerReplyKind.success) {
        metrics.connectCompleted(
          pending.context,
          completed,
          connectionId: pending.connectionId,
        );
        if (pending.connectionId != null && pending.context.plane != null) {
          _activeConnectionIds[pending.connectionId!] = pending.context.plane!;
        }
      } else {
        metrics.connectFailed(
          pending.context,
          connectionId: pending.connectionId,
        );
      }
    }
    if (pending.operation == SshWorkerOperation.writeSftpChunk &&
        reply.kind == SshWorkerReplyKind.success) {
      metrics.sftpChunk(pending.context, pending.sftpPayloadByteCount ?? 0);
    }
    if (pending.operation == SshWorkerOperation.readSftpChunk &&
        reply.kind == SshWorkerReplyKind.success) {
      metrics.sftpChunk(
        pending.context,
        _base64ByteCount(reply.result['bytes']),
      );
    }
    if (reply.kind == SshWorkerReplyKind.success) {
      _completeForwardLifecycle(pending, metrics);
    } else if (_isForwardOpen(pending.operation) &&
        pending.connectionId != null) {
      // A channel-open event can race its failed open reply. Never leave its
      // identifier suppressing terminal accounting after that failure.
      _removeForward(pending.connectionId!);
    }
    metrics.pendingMessagesChanged(_pending.length);
  }

  void _recordEventMetrics(SshWorkerEvent event) {
    final metrics = _metrics;
    if (event.kind == SshWorkerEventKind.forwardClosed &&
        event.forwardId != null) {
      _markForwardClosed(event.forwardId!);
      final removed = _activeConnectionIds.remove(event.forwardId!);
      if (metrics == null || !metrics.enabled) return;
      if (removed != null) {
        metrics.connectionClosed(
          _eventMetricContext(event, SshWorkerMetricPlane.forwarding),
          connectionId: event.forwardId!,
        );
      }
      return;
    }
    if (event.kind == SshWorkerEventKind.transportClose &&
        event.plane != null) {
      final closed = _closeConnectionsForPlane(event);
      if (metrics == null || !metrics.enabled) return;
      final plane = event.plane == SshTransportPlane.storage
          ? SshWorkerMetricPlane.storage
          : SshWorkerMetricPlane.member;
      for (final connectionId in closed) {
        metrics.connectionClosed(
          _eventMetricContext(event, plane),
          connectionId: connectionId,
        );
      }
      return;
    }
    if (metrics == null || !metrics.enabled) return;
    if (event.kind == SshWorkerEventKind.forwardChannelOpened &&
        event.channelId != null) {
      final forwardId = event.forwardId;
      if (forwardId != null) {
        _forwardStreamIds.add(forwardId);
        _forwardStreamIds.add(event.channelId!);
        (_forwardChannels[forwardId] ??= <String>{}).add(event.channelId!);
        _forwardStreamOwners[event.channelId!] = forwardId;
      }
      return;
    }
    if (event.kind == SshWorkerEventKind.outputChunk && event.bytes != null) {
      if (!_forwardStreamIds.contains(event.streamId)) {
        metrics.terminalFrame(
          _eventMetricContext(event, SshWorkerMetricPlane.member),
          event.bytes!.length,
        );
      }
      if (event.isFinal == true) _removeForwardStream(event.streamId);
      return;
    }
    if (event.kind == SshWorkerEventKind.execOutput && event.bytes != null) {
      metrics.terminalFrame(
        _eventMetricContext(event, SshWorkerMetricPlane.member),
        event.bytes!.length,
      );
    }
  }

  SshWorkerMetricContext _metricContext(SshWorkerRequest request) =>
      SshWorkerMetricContext(
        profileId: profileId,
        generation: generation,
        plane: _planeFor(request.operation),
        requestId: request.requestId,
        streamId: _requestStreamId(request),
      );

  SshWorkerMetricContext _eventMetricContext(
    SshWorkerEvent event,
    SshWorkerMetricPlane plane,
  ) => SshWorkerMetricContext(
    profileId: profileId,
    generation: generation,
    plane: plane,
    streamId: event.streamId,
  );

  String? _connectionId(SshWorkerRequest request) {
    if (!_isConnectionRequest(request.operation)) {
      if (request.operation == SshWorkerOperation.closeForward ||
          request.operation == SshWorkerOperation.closeChannel) {
        for (final key in ['forwardId', 'channelId']) {
          final value = request.args[key];
          if (value is String && _activeConnectionIds.containsKey(value)) {
            return value;
          }
        }
      }
      return null;
    }
    if (request.operation == SshWorkerOperation.connectStorage) {
      return '$profileId:storage';
    }
    for (final key in ['memberId', 'forwardId']) {
      final value = request.args[key];
      if (value is String) return value;
    }
    return null;
  }

  void _completeForwardLifecycle(
    _PendingMetric pending,
    SshWorkerMetrics metrics,
  ) {
    if (_isForwardOpen(pending.operation) && pending.connectionId != null) {
      final forwardId = pending.connectionId!;
      _forwardStreamIds.add(forwardId);
      _forwardStreamOwners[forwardId] = forwardId;
      final channels = _forwardChannels.putIfAbsent(forwardId, () => {});
      if (pending.operation == SshWorkerOperation.openForwardLocal) {
        channels.add(forwardId);
      }
    }
    if (pending.operation == SshWorkerOperation.closeForward &&
        pending.connectionId != null) {
      _markForwardClosed(pending.connectionId!);
      _activeConnectionIds.remove(pending.connectionId);
      metrics.connectionClosed(
        pending.context,
        connectionId: pending.connectionId!,
      );
    }
    if (pending.operation == SshWorkerOperation.closeChannel &&
        pending.connectionId != null &&
        _activeConnectionIds.remove(pending.connectionId) != null) {
      metrics.connectionClosed(
        pending.context,
        connectionId: pending.connectionId!,
      );
    }
  }

  void _removeForward(String forwardId) {
    final channels = _forwardChannels.remove(forwardId);
    if (channels != null) {
      for (final channelId in channels) {
        _forwardStreamIds.remove(channelId);
        _forwardStreamOwners.remove(channelId);
      }
    }
    _forwardStreamIds.remove(forwardId);
    _forwardStreamOwners.remove(forwardId);
  }

  void _markForwardClosed(String forwardId) {
    final channels = _forwardChannels[forwardId];
    if (channels == null) {
      _removeForward(forwardId);
      return;
    }
    // Keep the forward and every channel classified as forwarding until the
    // channel's final output event has crossed this client boundary. A close
    // event is emitted before the worker drains those final events.
    if (channels.isEmpty) {
      _removeForward(forwardId);
    }
  }

  void _removeForwardStream(String? streamId) {
    if (streamId == null) return;
    final owner = _forwardStreamOwners.remove(streamId);
    _forwardStreamIds.remove(streamId);
    if (owner == null) return;
    final channels = _forwardChannels[owner];
    channels?.remove(streamId);
    if (channels != null && channels.isEmpty) _removeForward(owner);
  }

  List<String> _closeConnectionsForPlane(SshWorkerEvent event) {
    final plane = event.plane == SshTransportPlane.storage
        ? SshWorkerMetricPlane.storage
        : SshWorkerMetricPlane.member;
    final closed = _activeConnectionIds.entries
        .where(
          (entry) =>
              entry.value == plane &&
              (event.streamId == null || entry.key == event.streamId),
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final connectionId in closed) {
      _activeConnectionIds.remove(connectionId);
    }
    return closed;
  }

  void _clearForwardTracking() {
    _forwardStreamIds.clear();
    _forwardChannels.clear();
    _forwardStreamOwners.clear();
  }
}

final class _PendingMetric {
  _PendingMetric({
    required this.operation,
    required this.context,
    this.connectionId,
    this.sftpPayloadByteCount,
  });

  final SshWorkerOperation operation;
  final SshWorkerMetricContext context;
  final String? connectionId;
  final int? sftpPayloadByteCount;
  var isConnection = false;
}

final class _PendingConnection {
  const _PendingConnection({required this.id, required this.plane});

  final String id;
  final SshWorkerMetricPlane plane;
}

SshWorkerMetricPlane? _planeFor(SshWorkerOperation operation) =>
    switch (operation) {
      SshWorkerOperation.connectStorage ||
      SshWorkerOperation.runStorage ||
      SshWorkerOperation.openSftpRead ||
      SshWorkerOperation.readSftpChunk ||
      SshWorkerOperation.openSftpWrite ||
      SshWorkerOperation.writeSftpChunk ||
      SshWorkerOperation.closeSftpStream ||
      SshWorkerOperation.acknowledgeSftpChunk ||
      SshWorkerOperation.statSftp ||
      SshWorkerOperation.listSftpDirectory ||
      SshWorkerOperation.readlinkSftp ||
      SshWorkerOperation.realpathSftp ||
      SshWorkerOperation.mkdirSftp ||
      SshWorkerOperation.removeSftp => SshWorkerMetricPlane.storage,
      SshWorkerOperation.openMember ||
      SshWorkerOperation.runMember ||
      SshWorkerOperation.startMemberExec ||
      SshWorkerOperation.writeMemberExec ||
      SshWorkerOperation.closeMemberExecStdin ||
      SshWorkerOperation.killMemberExec ||
      SshWorkerOperation.acknowledgeExecOutput ||
      SshWorkerOperation.openPty ||
      SshWorkerOperation.writePty ||
      SshWorkerOperation.resizePty ||
      SshWorkerOperation.acknowledgePtyOutput ||
      SshWorkerOperation.closeChannel => SshWorkerMetricPlane.member,
      SshWorkerOperation.openForwardLocal ||
      SshWorkerOperation.openForwardRemote ||
      SshWorkerOperation.writeForwardChannel ||
      SshWorkerOperation.acknowledgeForwardOutput ||
      SshWorkerOperation.closeForwardChannel ||
      SshWorkerOperation.closeForward => SshWorkerMetricPlane.forwarding,
      SshWorkerOperation.disconnectStorage ||
      SshWorkerOperation.cancelRequest ||
      SshWorkerOperation.shutdown => null,
    };

bool _isConnectionRequest(SshWorkerOperation operation) =>
    operation == SshWorkerOperation.connectStorage ||
    operation == SshWorkerOperation.openMember ||
    operation == SshWorkerOperation.openForwardLocal ||
    operation == SshWorkerOperation.openForwardRemote;

bool _isForwardOpen(SshWorkerOperation operation) =>
    operation == SshWorkerOperation.openForwardLocal ||
    operation == SshWorkerOperation.openForwardRemote;

String? _requestStreamId(SshWorkerRequest request) {
  for (final key in ['streamId', 'ptyId', 'execId', 'channelId', 'forwardId']) {
    final value = request.args[key];
    if (value is String) return value;
  }
  return null;
}

int _base64ByteCount(Object? value) {
  if (value is! String || value.isEmpty) return 0;
  var padding = 0;
  if (value.endsWith('==')) {
    padding = 2;
  } else if (value.endsWith('=')) {
    padding = 1;
  }
  return (value.length * 3 ~/ 4) - padding;
}
