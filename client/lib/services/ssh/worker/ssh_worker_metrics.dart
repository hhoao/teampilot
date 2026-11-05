import 'package:flutter/foundation.dart';

import '../../../utils/logging/logger.dart';

/// The worker connection area represented by a diagnostic measurement.
enum SshWorkerMetricPlane { storage, member, forwarding }

/// Correlation values allowed in worker diagnostic records.
///
/// This deliberately excludes request arguments, paths, commands, and binary
/// data. The identifiers make aggregate measurements traceable without
/// exposing SSH payloads.
final class SshWorkerMetricContext {
  const SshWorkerMetricContext({
    required this.profileId,
    required this.generation,
    this.plane,
    this.requestId,
    this.streamId,
  });

  final String profileId;
  final int generation;
  final SshWorkerMetricPlane? plane;
  final String? requestId;
  final String? streamId;

  SshWorkerMetricContext withRequestId(String value) => SshWorkerMetricContext(
    profileId: profileId,
    generation: generation,
    plane: plane,
    requestId: value,
    streamId: streamId,
  );

  SshWorkerMetricContext withStreamId(String value) => SshWorkerMetricContext(
    profileId: profileId,
    generation: generation,
    plane: plane,
    requestId: requestId,
    streamId: value,
  );
}

/// Immutable aggregate view of one enabled [SshWorkerMetrics] collector.
final class SshWorkerMetricsSnapshot {
  const SshWorkerMetricsSnapshot({
    required this.activeWorkers,
    required this.activeWorkerHighWaterMark,
    required this.pendingMessageHighWaterMark,
    required this.completedRequestLatencies,
    required this.connectLatencies,
    required this.reconnectLatencies,
    required this.workerShutdownDurations,
    required this.terminalBytesPerFrame,
    required this.terminalFrameCount,
    required this.terminalBytesTotal,
    required this.sftpBytesPerChunk,
    required this.sftpChunkCount,
    required this.sftpBytesTotal,
    required this.diagnosticContexts,
  });

  final int activeWorkers;
  final int activeWorkerHighWaterMark;
  final int pendingMessageHighWaterMark;
  final List<Duration> completedRequestLatencies;
  final List<Duration> connectLatencies;
  final List<Duration> reconnectLatencies;
  final List<Duration> workerShutdownDurations;
  final List<int> terminalBytesPerFrame;
  final int terminalFrameCount;
  final int terminalBytesTotal;
  final List<int> sftpBytesPerChunk;
  final int sftpChunkCount;
  final int sftpBytesTotal;

  /// Bounded, sanitized correlation contexts observed by this collector.
  final List<SshWorkerMetricContext> diagnosticContexts;
}

/// Collects bounded, diagnostics-only profile-worker aggregate metrics.
///
/// A manager only uses a collector supplied by its caller. Direct collectors
/// default off in release builds, while tests and debug capture can explicitly
/// opt in with [enabled]. No method accepts or logs payload content.
final class SshWorkerMetrics {
  SshWorkerMetrics({
    bool? enabled,
    DateTime Function()? now,
    void Function(String message)? logDiagnostic,
    this.sampleCapacity = 200,
  }) : enabled = enabled ?? !kReleaseMode,
       _now = now ?? DateTime.now,
       _logDiagnostic = logDiagnostic ?? AppLogger.instance.d {
    if (sampleCapacity < 1) {
      throw ArgumentError.value(
        sampleCapacity,
        'sampleCapacity',
        'Must be positive',
      );
    }
  }

  final bool enabled;
  final DateTime Function() _now;
  final void Function(String message) _logDiagnostic;
  final int sampleCapacity;
  final Map<String, DateTime> _requestStarts = {};
  final Map<String, DateTime> _connectStarts = {};
  final Map<String, DateTime> _shutdownStarts = {};
  final Map<String, _ConnectionScope> _connectionScopes = {};
  final List<SshWorkerMetricContext> _diagnosticContexts = [];
  final Set<String> _diagnosticContextKeys = {};
  final List<Duration> _completedRequestLatencies = [];
  final List<Duration> _connectLatencies = [];
  final List<Duration> _reconnectLatencies = [];
  final List<Duration> _workerShutdownDurations = [];
  final List<int> _terminalBytesPerFrame = [];
  final List<int> _sftpBytesPerChunk = [];
  var _activeWorkers = 0;
  var _activeWorkerHighWaterMark = 0;
  var _pendingMessageHighWaterMark = 0;
  var _terminalFrameCount = 0;
  var _terminalBytesTotal = 0;
  var _sftpChunkCount = 0;
  var _sftpBytesTotal = 0;

  DateTime now() => _now();

  SshWorkerMetricsSnapshot get snapshot => SshWorkerMetricsSnapshot(
    activeWorkers: _activeWorkers,
    activeWorkerHighWaterMark: _activeWorkerHighWaterMark,
    pendingMessageHighWaterMark: _pendingMessageHighWaterMark,
    completedRequestLatencies: List.unmodifiable(_completedRequestLatencies),
    connectLatencies: List.unmodifiable(_connectLatencies),
    reconnectLatencies: List.unmodifiable(_reconnectLatencies),
    workerShutdownDurations: List.unmodifiable(_workerShutdownDurations),
    terminalBytesPerFrame: List.unmodifiable(_terminalBytesPerFrame),
    terminalFrameCount: _terminalFrameCount,
    terminalBytesTotal: _terminalBytesTotal,
    sftpBytesPerChunk: List.unmodifiable(_sftpBytesPerChunk),
    sftpChunkCount: _sftpChunkCount,
    sftpBytesTotal: _sftpBytesTotal,
    diagnosticContexts: List.unmodifiable(_diagnosticContexts),
  );

  void workerStarted(SshWorkerMetricContext context) {
    if (!enabled) return;
    _rememberContext(context);
    _activeWorkers++;
    if (_activeWorkers > _activeWorkerHighWaterMark) {
      _activeWorkerHighWaterMark = _activeWorkers;
    }
  }

  void workerShutdownStarted(SshWorkerMetricContext context, DateTime started) {
    if (!enabled) return;
    _rememberContext(context);
    _shutdownStarts[_workerKey(context)] = started;
  }

  void workerShutdownCompleted(
    SshWorkerMetricContext context,
    DateTime completed,
  ) {
    if (!enabled) return;
    _rememberContext(context);
    final started = _shutdownStarts.remove(_workerKey(context));
    if (started != null) {
      _addDuration(_workerShutdownDurations, completed.difference(started));
    }
    if (_activeWorkers > 0) _activeWorkers--;
  }

  void requestStarted(
    String requestId,
    DateTime started, {
    SshWorkerMetricContext? context,
  }) {
    if (!enabled) return;
    if (context != null) _rememberContext(context);
    _requestStarts[_requestKey(requestId, context)] = started;
  }

  void requestCompleted(
    String requestId,
    DateTime completed, {
    SshWorkerMetricContext? context,
  }) {
    if (!enabled) return;
    if (context != null) _rememberContext(context);
    final started = _requestStarts.remove(_requestKey(requestId, context));
    if (started != null) {
      _addDuration(_completedRequestLatencies, completed.difference(started));
    }
  }

  void pendingMessagesChanged(int pendingMessages) {
    if (!enabled || pendingMessages <= _pendingMessageHighWaterMark) return;
    _pendingMessageHighWaterMark = pendingMessages;
  }

  void connectStarted(
    SshWorkerMetricContext context,
    DateTime started, {
    String? connectionId,
  }) {
    if (!enabled || context.requestId == null) return;
    _rememberContext(context);
    _connectStarts[_requestKey(context.requestId!, context)] = started;
  }

  void connectCompleted(
    SshWorkerMetricContext context,
    DateTime completed, {
    String? connectionId,
  }) {
    if (!enabled || context.requestId == null) return;
    _rememberContext(context);
    final started = _connectStarts.remove(
      _requestKey(context.requestId!, context),
    );
    if (started == null) return;
    final scope = _connectionScopes.putIfAbsent(
      _connectionScopeKey(context),
      () => _ConnectionScope(profileId: context.profileId),
    );
    final sessionKey = _connectionSessionKey(context, connectionId);
    final isNewSession = !scope.activeSessions.containsKey(sessionKey);
    scope.activeSessions[sessionKey] = context.generation;
    final isReconnect = isNewSession && scope.reconnectSlots > 0;
    if (isReconnect) scope.reconnectSlots--;
    final samples = isReconnect ? _reconnectLatencies : _connectLatencies;
    _addDuration(samples, completed.difference(started));
  }

  void connectFailed(SshWorkerMetricContext context, {String? connectionId}) {
    if (!enabled || context.requestId == null) return;
    _rememberContext(context);
    _connectStarts.remove(_requestKey(context.requestId!, context));
  }

  /// Ends a logical connection and makes its slot eligible for replacement.
  void connectionClosed(
    SshWorkerMetricContext context, {
    required String connectionId,
  }) {
    if (!enabled) return;
    _rememberContext(context);
    final scope = _connectionScopes[_connectionScopeKey(context)];
    if (scope == null) return;
    final key = _connectionSessionKey(context, connectionId);
    if (scope.activeSessions.remove(key) != null) scope.reconnectSlots++;
  }

  /// Ends every logical connection owned by one worker generation.
  ///
  /// A later successful connection in the same profile and plane consumes one
  /// closed slot and is recorded as a reconnect, even when its generated
  /// session identifier differs from the prior generation.
  void workerGenerationClosed(SshWorkerMetricContext context) {
    if (!enabled) return;
    _rememberContext(context);
    for (final scope in _connectionScopes.values) {
      if (scope.profileId != context.profileId) continue;
      final closedKeys = scope.activeSessions.entries
          .where((entry) => entry.value == context.generation)
          .map((entry) => entry.key)
          .toList(growable: false);
      for (final key in closedKeys) {
        scope.activeSessions.remove(key);
      }
      scope.reconnectSlots += closedKeys.length;
    }
  }

  void terminalFrame(SshWorkerMetricContext context, int byteCount) {
    if (!enabled || byteCount < 0) return;
    _rememberContext(context);
    _terminalFrameCount++;
    _terminalBytesTotal += byteCount;
    _addSample(_terminalBytesPerFrame, byteCount);
  }

  void sftpChunk(SshWorkerMetricContext context, int byteCount) {
    if (!enabled || byteCount < 0) return;
    _rememberContext(context);
    _sftpChunkCount++;
    _sftpBytesTotal += byteCount;
    _addSample(_sftpBytesPerChunk, byteCount);
  }

  /// Emits a safe, aggregate snapshot with the supplied correlation values.
  void emitSnapshot(SshWorkerMetricContext context) {
    if (!enabled) return;
    _rememberContext(context);
    final current = snapshot;
    _logDiagnostic(
      'SSH worker metrics '
      'profileId=${context.profileId} '
      'generation=${context.generation} '
      'plane=${context.plane?.name ?? 'none'} '
      'requestId=${context.requestId ?? 'none'} '
      'streamId=${context.streamId ?? 'none'} '
      'activeWorkers=${current.activeWorkers} '
      'activeWorkerHighWaterMark=${current.activeWorkerHighWaterMark} '
      'pendingMessageHighWaterMark=${current.pendingMessageHighWaterMark} '
      'requestSamples=${current.completedRequestLatencies.length} '
      'connectSamples=${current.connectLatencies.length} '
      'reconnectSamples=${current.reconnectLatencies.length} '
      'shutdownSamples=${current.workerShutdownDurations.length} '
      'requestLatencyUs=${_durationMicros(current.completedRequestLatencies)} '
      'connectLatencyUs=${_durationMicros(current.connectLatencies)} '
      'reconnectLatencyUs=${_durationMicros(current.reconnectLatencies)} '
      'shutdownDurationUs=${_durationMicros(current.workerShutdownDurations)} '
      'terminalFrames=${current.terminalFrameCount} '
      'terminalBytes=${current.terminalBytesTotal} '
      'sftpChunks=${current.sftpChunkCount} sftpBytes=${current.sftpBytesTotal}',
    );
  }

  void _rememberContext(SshWorkerMetricContext context) {
    final key = [
      context.profileId,
      context.generation,
      context.plane?.name,
      context.requestId,
      context.streamId,
    ].join('|');
    if (!_diagnosticContextKeys.add(key)) return;
    _diagnosticContexts.add(context);
    if (_diagnosticContexts.length > sampleCapacity) {
      final removed = _diagnosticContexts.removeAt(0);
      _diagnosticContextKeys.remove(_contextKey(removed));
    }
  }

  String _contextKey(SshWorkerMetricContext context) => [
    context.profileId,
    context.generation,
    context.plane?.name,
    context.requestId,
    context.streamId,
  ].join('|');

  void _addDuration(List<Duration> values, Duration value) =>
      _addSample(values, value.isNegative ? Duration.zero : value);

  String _durationMicros(List<Duration> values) => values.isEmpty
      ? 'none'
      : values.map((value) => value.inMicroseconds).join(',');

  void _addSample<T>(List<T> values, T value) {
    values.add(value);
    if (values.length > sampleCapacity) values.removeAt(0);
  }

  String _workerKey(SshWorkerMetricContext context) =>
      '${context.profileId}:${context.generation}';

  String _requestKey(String requestId, SshWorkerMetricContext? context) =>
      context == null ? requestId : '${_workerKey(context)}:$requestId';

  String _connectionScopeKey(SshWorkerMetricContext context) =>
      '${context.profileId}:${context.plane?.name ?? 'none'}';

  String _connectionSessionKey(
    SshWorkerMetricContext context,
    String? connectionId,
  ) => '${context.generation}:${connectionId ?? context.plane?.name ?? 'none'}';
}

final class _ConnectionScope {
  _ConnectionScope({required this.profileId});

  final String profileId;
  final Map<String, int> activeSessions = {};
  var reconnectSlots = 0;
}
