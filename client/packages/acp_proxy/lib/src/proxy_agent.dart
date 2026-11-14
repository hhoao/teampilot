import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acpd/acpd.dart';

import 'idle_policy.dart';
import 'launch_meta.dart';
import 'permission_policy.dart';
import 'session_book.dart';
import 'spool.dart';
import 'upstream.dart';

const _permissionMethod = 'session/request_permission';
const _askQuestionMethod = 'cursor/ask_question';
const _createPlanMethod = 'cursor/create_plan';

/// ACP agent the phone talks to. The CLI upstream stays up across disconnects.
class AcpProxyAgent {
  AcpProxyAgent({
    required this.endpointCli,
    required this.book,
    required this.spool,
    required this.upstreams,
    this.permissionTimeout = acpProxyPermissionTimeout,
  });

  final String endpointCli;
  final AcpProxySessionBook book;
  final AcpProxySpool spool;

  /// Keyed by ACP session id. Tests insert fakes. Production creates them
  /// from [openNew] / [openLoad].
  final Map<String, AcpUpstream> upstreams;

  /// How long a disconnected permission or cursor question stays open.
  final Duration permissionTimeout;

  /// Factory used the first time a session id is unknown.
  /// Tests set this. Default throws [StateError] `'no upstream'`.
  Future<AcpUpstream> Function({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  })?
  connectNew;

  /// Set when the phone leg becomes null. Cleared when a connection attaches.
  /// Task 8 reads this for the idle reap.
  final Map<String, DateTime> disconnectedSince = {};

  final Map<String, _PhoneLeg> _legs = {};
  final Map<String, _PhoneLeg> _sessionLeg = {};
  final Map<String, AcpProxyLaunchMeta> _metas = {};
  final Set<String> _sessionIds = {};
  final Map<String, AcpUpstream> _watched = {};
  final Map<String, StreamSubscription<Map<String, Object?>>> _updateSubs = {};
  final Map<String, StreamSubscription<AcpClientRequest>> _requestSubs = {};
  final Map<String, _ReplayGate> _gates = {};

  /// Serializes load, new, and close for one session id.
  final Map<String, Future<void>> _sessionTails = {};

  /// CLI history captured before a spool read failed. The next load merges it.
  final Map<String, List<Map<String, Object?>>> _retainedCli = {};
  final Map<String, List<Completer<PromptResponse>>> _promptWaiters = {};
  final Map<String, List<_Held>> _held = {};
  final Map<String, int> _permissionPendingCounts = {};
  var _nextConnectionId = 0;

  /// True while a disconnected permission or cursor question is still open.
  bool permissionPending(String sessionId) =>
      (_permissionPendingCounts[sessionId] ?? 0) > 0;

  /// Whether the idle clock may advance. A pending permission holds it.
  bool idleClockRunning(String sessionId) {
    return shouldRunIdleTimer(
      phoneConnected: book.connectionFor(sessionId) != null,
      turnInProgress: book.turnInProgress(sessionId),
      permissionPending: permissionPending(sessionId),
    );
  }

  /// Closes sessions idle for [idleTimeout], using the same per-session
  /// cleanup as `session/close`. A turn or permission wait restarts the clock
  /// at [now] instead of closing.
  Future<void> reapIdle({
    required DateTime now,
    required Duration idleTimeout,
  }) {
    return reapIdleSessions(
      book: book,
      spool: spool,
      upstreams: upstreams,
      disconnectedSince: disconnectedSince,
      now: now,
      idleTimeout: idleTimeout,
      permissionPending: permissionPending,
      closeSession: _closeKeptSession,
    );
  }

  /// Builds an [AgentRole] and connects it to [phone].
  AgentConnection serve(Transport phone) {
    late final AgentConnection connection;
    final role = AgentRole()
        .onInitialize((context, request, cancellation) {
          return _onInitialize(request);
        })
        .onNewSession((context, request, cancellation) {
          return _onNewSession(connection, request);
        })
        .onLoadSession((context, request, cancellation) {
          return _onLoad(connection, context, request);
        })
        .onResumeSession((context, request, cancellation) {
          return _onResume(connection, context, request);
        })
        .onPrompt((context, request, cancellation) {
          return _onPrompt(request);
        })
        .onSessionCancel((context, notification) {
          return _onCancel(notification);
        })
        .onCloseSession((context, request, cancellation) {
          return _onClose(request);
        });
    connection = role.connect(phone);
    final leg = _PhoneLeg('c${_nextConnectionId++}', connection);
    _legs[leg.id] = leg;
    connection.connection.onClose.listen((_) => _onPhoneDone(leg));
    return connection;
  }

  InitializeResponse _onInitialize(InitializeRequest _) {
    return const InitializeResponse(
      protocolVersion: ProtocolVersion.v1,
      agentCapabilities: AgentCapabilities(loadSession: true),
    );
  }

  Future<NewSessionResponse> _onNewSession(
    AgentConnection connection,
    NewSessionRequest request,
  ) async {
    final AcpProxyLaunchMeta meta;
    try {
      meta = AcpProxyLaunchMeta.parse(
        endpointCli: endpointCli,
        meta: request.meta,
      );
    } on FormatException catch (error) {
      throw RpcError.fromCode(ErrorCode.invalidParams, data: error.message);
    }

    final mcpServers = _mcpMaps(request.mcpServers);
    final upstream = await _connect(
      meta: meta,
      cwd: request.cwd,
      mcpServers: mcpServers,
    );
    final capture = _capture(upstream);
    final String sessionId;
    try {
      sessionId = await upstream.openNew(
        meta: meta,
        cwd: request.cwd,
        mcpServers: mcpServers,
      );
    } catch (error) {
      await _closeQuiet(upstream);
      await capture.cancel();
      throw _surface(error);
    }
    if (!isSafeAcpProxySessionId(sessionId)) {
      await _closeQuiet(upstream);
      await capture.cancel();
      throw RpcError.fromCode(
        ErrorCode.invalidParams,
        data: 'session id must be one path segment',
      );
    }
    try {
      return await _withSessionLock(sessionId, () async {
        try {
          final cliHistory = capture.takeUpdates();
          await _remember(
            sessionId: sessionId,
            meta: meta,
            cwd: request.cwd,
            upstream: upstream,
          );
          await _playAndAttach(
            context: connection.agent,
            sessionId: sessionId,
            leg: _legFor(connection),
            cliHistory: cliHistory,
            capture: capture,
            upstream: upstream,
          );
          return NewSessionResponse(sessionId: sessionId);
        } catch (error) {
          await _cleanupUnattached(sessionId, upstream, capture);
          throw _surface(error);
        }
      });
    } catch (error) {
      throw _surface(error);
    }
  }

  Future<void> _cleanupUnattached(
    String sessionId,
    AcpUpstream upstream,
    _Capture capture,
  ) async {
    if (book.connectionFor(sessionId) == null) {
      await _stopWatching(sessionId);
      if (identical(upstreams[sessionId], upstream)) {
        upstreams.remove(sessionId);
        await _closeQuiet(upstream);
      }
      _metas.remove(sessionId);
      _sessionIds.remove(sessionId);
      _sessionLeg.remove(sessionId);
      disconnectedSince.remove(sessionId);
      _gates.remove(sessionId);
      _retainedCli.remove(sessionId);
      try {
        await spool.delete(sessionId);
      } on Object {
        // The session never became visible to the phone.
      }
    }
    await capture.cancel();
  }

  Future<LoadSessionResponse> _onLoad(
    AgentConnection connection,
    AgentContext context,
    LoadSessionRequest request,
  ) {
    return _load(
      connection: connection,
      context: context,
      sessionId: request.sessionId,
      cwd: request.cwd,
      mcpServers: request.mcpServers,
      meta: request.meta,
    );
  }

  Future<LoadSessionResponse> _onResume(
    AgentConnection connection,
    AgentContext context,
    ResumeSessionRequest request,
  ) {
    return _load(
      connection: connection,
      context: context,
      sessionId: request.sessionId,
      cwd: request.cwd,
      mcpServers: request.mcpServers,
      meta: request.meta,
    );
  }

  Future<LoadSessionResponse> _load({
    required AgentConnection connection,
    required AgentContext context,
    required String sessionId,
    required String cwd,
    required List<McpServer> mcpServers,
    required Map<String, Object?> meta,
  }) {
    if (!isSafeAcpProxySessionId(sessionId)) {
      throw RpcError.fromCode(
        ErrorCode.invalidParams,
        data: 'session id must be one path segment',
      );
    }
    return _withSessionLock(
      sessionId,
      () => _loadLocked(
        connection: connection,
        context: context,
        sessionId: sessionId,
        cwd: cwd,
        mcpServers: mcpServers,
        meta: meta,
      ),
    );
  }

  Future<LoadSessionResponse> _loadLocked({
    required AgentConnection connection,
    required AgentContext context,
    required String sessionId,
    required String cwd,
    required List<McpServer> mcpServers,
    required Map<String, Object?> meta,
  }) async {
    final existing = upstreams[sessionId];
    if (existing != null && existing.alive) {
      await _playAndAttach(
        context: context,
        sessionId: sessionId,
        leg: _legFor(connection),
        cliHistory: const [],
      );
      return const LoadSessionResponse();
    }
    if (existing != null) {
      await _stopWatching(sessionId);
      if (identical(upstreams[sessionId], existing)) {
        upstreams.remove(sessionId);
      }
      await _closeQuiet(existing);
    }

    final AcpProxyLaunchMeta launch;
    try {
      launch = _metaFor(sessionId, meta);
    } on FormatException catch (error) {
      throw RpcError.fromCode(ErrorCode.invalidParams, data: error.message);
    }
    final upstream = await _connect(
      meta: launch,
      cwd: cwd,
      mcpServers: _mcpMaps(mcpServers),
    );
    await _stopWatching(sessionId);
    final capture = _capture(upstream);
    try {
      await upstream.openLoad(sessionId: sessionId, cwd: cwd);
    } catch (error) {
      await capture.cancel();
      await _closeQuiet(upstream);
      throw _surface(error);
    }
    final cliHistory = capture.takeUpdates();
    try {
      await _remember(
        sessionId: sessionId,
        meta: launch,
        cwd: cwd,
        upstream: upstream,
      );
      await _playAndAttach(
        context: context,
        sessionId: sessionId,
        leg: _legFor(connection),
        cliHistory: cliHistory,
        capture: capture,
        upstream: upstream,
      );
    } catch (error) {
      if (!capture.bound) await capture.cancel();
      rethrow;
    }
    return const LoadSessionResponse();
  }

  Future<PromptResponse> _onPrompt(PromptRequest request) async {
    final text = _promptText(request);
    final AcpProxyPromptDisposition disposition;
    try {
      disposition = book.onPrompt(sessionId: request.sessionId, text: text);
    } on StateError catch (error) {
      throw RpcError.fromCode(ErrorCode.invalidParams, data: error.message);
    }
    final upstream = upstreams[request.sessionId];
    if (upstream == null) {
      throw RpcError(
        code: ErrorCode.internalError.code,
        message: 'no upstream',
      );
    }
    final waiter = _waitForStop(request.sessionId);
    if (disposition == AcpProxyPromptDisposition.start) {
      try {
        await upstream.prompt(text);
      } catch (error) {
        _dropWaiter(request.sessionId, waiter);
        book.finishTurn(request.sessionId);
        throw _surface(error);
      }
    }
    return waiter.future;
  }

  Future<void> _onCancel(CancelNotification notification) async {
    final upstream = upstreams[notification.sessionId];
    if (upstream == null) return;
    await upstream.cancel();
  }

  Future<CloseSessionResponse> _onClose(CloseSessionRequest request) async {
    await _closeKeptSession(request.sessionId);
    return const CloseSessionResponse();
  }

  /// `session/close` and idle expiry share this cleanup.
  Future<void> _closeKeptSession(String sessionId) {
    return _withSessionLock(
      sessionId,
      () => _closeKeptSessionLocked(sessionId),
    );
  }

  Future<void> _closeKeptSessionLocked(String sessionId) async {
    requireSafeAcpProxySessionId(sessionId);
    await _stopWatching(sessionId);
    final upstream = upstreams.remove(sessionId);
    _releaseHeld(sessionId);
    _cancelOpenTurn(sessionId);
    if (upstream != null) await _closeQuiet(upstream);
    await spool.delete(sessionId);
    book.forget(sessionId);
    _metas.remove(sessionId);
    _sessionLeg.remove(sessionId);
    _sessionIds.remove(sessionId);
    disconnectedSince.remove(sessionId);
    _retainedCli.remove(sessionId);
    _gates.remove(sessionId);
  }

  Future<T> _withSessionLock<T>(
    String sessionId,
    Future<T> Function() body,
  ) async {
    final previous = _sessionTails[sessionId] ?? Future<void>.value();
    final gate = Completer<void>();
    _sessionTails[sessionId] = gate.future;
    try {
      await previous.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return await body();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_sessionTails[sessionId], gate.future)) {
        _sessionTails.remove(sessionId);
      }
    }
  }

  Future<void> _remember({
    required String sessionId,
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required AcpUpstream upstream,
  }) async {
    if (!_spoolReady(sessionId)) {
      try {
        await spool.create(sessionId: sessionId, cwd: cwd, meta: meta);
      } catch (error) {
        await _closeQuiet(upstream);
        throw _surface(error);
      }
    }
    upstreams[sessionId] = upstream;
    _metas[sessionId] = meta;
    _sessionIds.add(sessionId);
  }

  Future<AcpUpstream> _connect({
    required AcpProxyLaunchMeta meta,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
  }) {
    final factory = connectNew;
    if (factory == null) throw StateError('no upstream');
    return factory(meta: meta, cwd: cwd, mcpServers: mcpServers);
  }

  AcpProxyLaunchMeta _metaFor(String sessionId, Map<String, Object?> meta) {
    if (meta['teampilot'] is Map) {
      return AcpProxyLaunchMeta.parse(endpointCli: endpointCli, meta: meta);
    }
    final stored = _metas[sessionId];
    if (stored != null) return stored;
    return AcpProxyLaunchMeta.parse(endpointCli: endpointCli, meta: meta);
  }

  Future<void> _attach(String sessionId, _PhoneLeg leg) async {
    book.attach(sessionId: sessionId, connectionId: leg.id);
    disconnectedSince.remove(sessionId);
    final previous = _sessionLeg[sessionId];
    _sessionLeg[sessionId] = leg;
    _flushHeld(sessionId, leg);
    if (previous != null &&
        !identical(previous, leg) &&
        !_sessionLeg.values.contains(previous)) {
      await previous.connection.close();
    }
  }

  void _onPhoneDone(_PhoneLeg leg) {
    _legs.remove(leg.id);
    book.detach(leg.id);
    for (final sessionId in _sessionIds.toList()) {
      if (!identical(_sessionLeg[sessionId], leg)) continue;
      if (book.connectionFor(sessionId) != null) continue;
      disconnectedSince[sessionId] = DateTime.now();
      _sessionLeg.remove(sessionId);
    }
  }

  _PhoneLeg _legFor(AgentConnection connection) {
    for (final leg in _legs.values) {
      if (identical(leg.connection, connection)) return leg;
    }
    throw StateError('phone leg missing');
  }

  _Capture _capture(AcpUpstream upstream) {
    final capture = _Capture();
    void end() => _onUpstreamEnded(capture, upstream);
    capture.updateSub = upstream.updates.listen(
      (update) {
        if (capture.hold || capture.sessionId == null) {
          capture.updates.add(update);
          return;
        }
        _onUpstreamUpdate(capture.sessionId!, update);
      },
      onError: (Object _, StackTrace _) => end(),
      onDone: end,
      cancelOnError: true,
    );
    capture.requestSub = upstream.clientRequests.listen(
      (request) {
        if (capture.hold || capture.sessionId == null) {
          capture.requests.add(request);
          return;
        }
        _onClientRequest(capture.sessionId!, upstream, request);
      },
      onError: (Object _, StackTrace _) => end(),
      onDone: end,
      cancelOnError: true,
    );
    return capture;
  }

  /// CLI stdout closed without a stop. End the turn so idle and the next
  /// prompt are not stuck waiting.
  void _onUpstreamEnded(_Capture capture, AcpUpstream upstream) {
    if (capture.ended) return;
    capture.ended = true;
    final sessionId = capture.sessionId;
    if (sessionId == null || !identical(_watched[sessionId], upstream)) {
      return;
    }
    _cancelOpenTurn(sessionId);
    _releaseHeld(sessionId);
  }

  void _cancelOpenTurn(String sessionId) {
    final waiters = _promptWaiters.remove(sessionId);
    if (waiters != null) {
      for (final waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.complete(
            const PromptResponse(stopReason: StopReason.cancelled),
          );
        }
      }
    }
    book.finishTurn(sessionId);
  }

  void _bindCapture(String sessionId, AcpUpstream upstream, _Capture capture) {
    final previousUpdate = _updateSubs.remove(sessionId);
    if (!identical(previousUpdate, capture.updateSub)) {
      previousUpdate?.cancel();
    }
    final previousRequest = _requestSubs.remove(sessionId);
    if (!identical(previousRequest, capture.requestSub)) {
      previousRequest?.cancel();
    }
    capture.sessionId = sessionId;
    capture.bound = true;
    _watched[sessionId] = upstream;
    _updateSubs[sessionId] = capture.updateSub!;
    _requestSubs[sessionId] = capture.requestSub!;
    if (capture.ended) {
      _cancelOpenTurn(sessionId);
      _releaseHeld(sessionId);
    }
  }

  /// Sends CLI history, then spool lines it does not include, then the live
  /// tail. That same order is written back to the spool. The previous phone
  /// stays up until the read succeeds.
  Future<void> _playAndAttach({
    required AgentContext context,
    required String sessionId,
    required _PhoneLeg leg,
    required List<Map<String, Object?>> cliHistory,
    _Capture? capture,
    AcpUpstream? upstream,
  }) async {
    if (capture != null && upstream != null) {
      _bindCapture(sessionId, upstream, capture);
    }
    final history = <Map<String, Object?>>[
      ..._retainedCli[sessionId] ?? const [],
      ...cliHistory,
    ];
    final gate = _ReplayGate();
    _gates[sessionId] = gate;
    if (capture != null) {
      final extras = capture.takeUpdates();
      gate.requests.addAll(capture.takeRequests());
      capture.hold = false;
      for (final extra in extras) {
        _onUpstreamUpdate(sessionId, extra);
      }
    }
    // Lines already on disk before the yield. Chunks that append during
    // [readAll] land in [gate] and, when the read sees them, in the snapshot.
    final pendingMark = gate.pending.length;
    final lineMark = _spoolLines(sessionId);
    final List<Map<String, Object?>> spooled;
    try {
      spooled = await spool.readAll(sessionId);
    } catch (error) {
      await _preserveHistory(sessionId, history);
      _abandonReplay(sessionId, gate);
      throw _surface(error);
    }
    var landed = spooled.length - lineMark;
    if (landed < 0) landed = 0;
    final tailStart = pendingMark + landed;
    final tail = <Map<String, Object?>>[
      for (var i = tailStart; i < gate.pending.length; i++) gate.pending[i],
    ];
    final ordered = _orderedReplay(
      sessionId: sessionId,
      cliHistory: history,
      spooled: spooled,
      tail: tail,
    );
    try {
      _replaceSpool(sessionId, ordered);
    } catch (error) {
      await _keepHistoryAfterFailedReplace(sessionId, history);
      _abandonReplay(sessionId, gate);
      throw _surface(error);
    }
    _retainedCli.remove(sessionId);
    final baseline = gate.pending.length;
    _emitOrdered(context, sessionId, ordered);
    var index = baseline;
    while (index < gate.pending.length) {
      final update = gate.pending[index++];
      if (update['sessionUpdate'] == 'stop') continue;
      _sendUpdate(context, sessionId, update);
    }
    final requests = List<AcpClientRequest>.from(gate.requests);
    _gates.remove(sessionId);
    await _attach(sessionId, leg);
    final current = upstreams[sessionId];
    if (current == null) return;
    for (final request in requests) {
      _onClientRequest(sessionId, current, request);
    }
  }

  /// Keeps [history] across a failed spool read. A readable rewrite lets the
  /// next live load replay it; otherwise the upstream is dropped so that load
  /// does not skip [AcpUpstream.openLoad] with the history gone.
  Future<void> _preserveHistory(
    String sessionId,
    List<Map<String, Object?>> history,
  ) async {
    if (history.isEmpty) return;
    try {
      final ordered = _orderedReplay(
        sessionId: sessionId,
        cliHistory: history,
        spooled: _readableSpoolLines(sessionId),
        tail: const [],
      );
      _replaceSpool(sessionId, ordered);
      _retainedCli.remove(sessionId);
    } on Object {
      _retainedCli[sessionId] = [
        for (final update in history) _normalizeMap(update),
      ];
      await _dropRememberedUpstream(sessionId);
    }
  }

  Future<void> _keepHistoryAfterFailedReplace(
    String sessionId,
    List<Map<String, Object?>> history,
  ) async {
    if (history.isNotEmpty) {
      _retainedCli[sessionId] = [
        for (final update in history) _normalizeMap(update),
      ];
    }
    if (_readableSpoolLines(sessionId).isEmpty) {
      await _dropRememberedUpstream(sessionId);
    }
  }

  Future<void> _dropRememberedUpstream(String sessionId) async {
    final upstream = upstreams.remove(sessionId);
    await _stopWatching(sessionId);
    if (upstream != null) await _closeQuiet(upstream);
  }

  List<Map<String, Object?>> _orderedReplay({
    required String sessionId,
    required List<Map<String, Object?>> cliHistory,
    required List<Map<String, Object?>> spooled,
    required List<Map<String, Object?>> tail,
  }) {
    final skip = <String, int>{};
    final ordered = <Map<String, Object?>>[];
    for (final update in cliHistory) {
      final stored = _normalizeMap(update);
      ordered.add(stored);
      if (stored['sessionUpdate'] == 'stop') {
        _completeStop(sessionId, stored);
        book.finishTurn(sessionId);
      } else {
        final key = _updateKey(stored);
        skip[key] = (skip[key] ?? 0) + 1;
      }
    }
    for (final update in spooled) {
      final stored = _normalizeMap(update);
      final left = skip[_updateKey(stored)] ?? 0;
      if (left > 0) {
        skip[_updateKey(stored)] = left - 1;
        continue;
      }
      ordered.add(stored);
    }
    for (final update in tail) {
      ordered.add(_normalizeMap(update));
    }
    return ordered;
  }

  void _emitOrdered(
    AgentContext context,
    String sessionId,
    List<Map<String, Object?>> ordered,
  ) {
    for (final update in ordered) {
      if (update['sessionUpdate'] == 'stop') continue;
      _sendUpdate(context, sessionId, update);
    }
  }

  void _replaceSpool(String sessionId, List<Map<String, Object?>> updates) {
    final file = _updatesFile(sessionId);
    if (!file.existsSync()) return;
    final buffer = StringBuffer();
    for (final update in updates) {
      buffer.write('${jsonEncode(_normalizeMap(update))}\n');
    }
    final tmp = File('${file.path}.tmp');
    try {
      tmp.writeAsStringSync(buffer.toString(), flush: true);
      if (!Platform.isWindows) {
        final chmod = Process.runSync('chmod', ['600', tmp.path]);
        if (chmod.exitCode != 0) {
          throw StateError('chmod 600 failed for ${tmp.path}');
        }
      }
      tmp.renameSync(file.path);
    } on Object {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } on Object {
          // The previous transcript is still at [file].
        }
      }
      rethrow;
    }
  }

  List<Map<String, Object?>> _readableSpoolLines(String sessionId) {
    final file = _updatesFile(sessionId);
    if (!file.existsSync()) return const [];
    final raw = file.readAsStringSync();
    if (raw.isEmpty) return const [];
    final updates = <Map<String, Object?>>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        updates.add(Map<String, Object?>.from(decoded));
      } on Object {
        // A torn line is omitted so the history ahead of it can be stored.
      }
    }
    return updates;
  }

  File _updatesFile(String sessionId) {
    requireSafeAcpProxySessionId(sessionId);
    return File(
      '${spool.root.path}/acp-proxy/sessions/$sessionId/updates.jsonl',
    );
  }

  void _abandonReplay(String sessionId, _ReplayGate gate) {
    if (identical(_gates[sessionId], gate)) _gates.remove(sessionId);
    final leg = _sessionLeg[sessionId];
    if (leg != null && book.connectionFor(sessionId) != null) {
      for (final update in gate.pending) {
        if (update['sessionUpdate'] == 'stop') continue;
        _sendUpdate(leg.context, sessionId, update);
      }
    }
    final upstream = upstreams[sessionId];
    if (upstream == null) return;
    for (final request in gate.requests) {
      _onClientRequest(sessionId, upstream, request);
    }
  }

  int _spoolLines(String sessionId) {
    final file = _updatesFile(sessionId);
    if (!file.existsSync()) return 0;
    final raw = file.readAsStringSync();
    if (raw.isEmpty) return 0;
    var count = 0;
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isNotEmpty) count++;
    }
    return count;
  }

  Future<void> _stopWatching(String sessionId) async {
    _watched.remove(sessionId);
    await _updateSubs.remove(sessionId)?.cancel();
    await _requestSubs.remove(sessionId)?.cancel();
  }

  void _onUpstreamUpdate(String sessionId, Map<String, Object?> update) {
    final stored = _normalizeMap(update);
    try {
      spool.appendUpdate(sessionId, stored);
    } on Object {
      // A missing spool must not drop the stop that ends the turn.
    }
    if (stored['sessionUpdate'] == 'stop') {
      _completeStop(sessionId, stored);
      book.finishTurn(sessionId);
      _gates[sessionId]?.pending.add(stored);
      return;
    }
    final gate = _gates[sessionId];
    if (gate != null) {
      gate.pending.add(stored);
      return;
    }
    final leg = _sessionLeg[sessionId];
    if (leg == null || book.connectionFor(sessionId) == null) return;
    _sendUpdate(leg.context, sessionId, stored);
  }

  void _completeStop(String sessionId, Map<String, Object?> update) {
    final waiters = _promptWaiters.remove(sessionId);
    if (waiters == null) return;
    final response = PromptResponse(stopReason: _stopReason(update));
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(response);
    }
  }

  void _sendUpdate(
    AgentContext context,
    String sessionId,
    Map<String, Object?> update,
  ) {
    final SessionUpdate parsed;
    try {
      parsed = SessionUpdate.fromJson(_normalizeMap(update));
    } on Object {
      return;
    }
    try {
      context.sessionUpdate(sessionId: sessionId, update: parsed);
    } on Object {
      // The phone leg can close between the book check and the write.
    }
  }

  void _onClientRequest(
    String sessionId,
    AcpUpstream upstream,
    AcpClientRequest request,
  ) {
    final gate = _gates[sessionId];
    if (gate != null) {
      gate.requests.add(request);
      return;
    }
    final leg = _sessionLeg[sessionId];
    if (leg != null && book.connectionFor(sessionId) != null) {
      unawaited(_forwardAndComplete(sessionId, upstream, leg, request));
      return;
    }
    _whenDisconnected(sessionId, upstream, request);
  }

  Future<void> _forwardAndComplete(
    String sessionId,
    AcpUpstream upstream,
    _PhoneLeg leg,
    AcpClientRequest request,
  ) async {
    try {
      final result = await _requestPhone(leg, request);
      upstream.completeClientRequest(request.id, result);
    } on Object {
      if (book.connectionFor(sessionId) == null ||
          !identical(_sessionLeg[sessionId], leg)) {
        _whenDisconnected(sessionId, upstream, request);
        return;
      }
      upstream.completeClientRequest(
        request.id,
        _terminalOutcome(request.method),
      );
    }
  }

  void _whenDisconnected(
    String sessionId,
    AcpUpstream upstream,
    AcpClientRequest request,
  ) {
    if (request.method == _permissionMethod) {
      final policy =
          _metas[sessionId]?.permissionPolicy ?? AcpProxyPermissionPolicy.ask;
      if (permissionActionWhenDisconnected(policy) ==
              DisconnectedPermissionAction.autoAllow &&
          _allow(upstream, request)) {
        return;
      }
      _hold(sessionId, upstream, request);
      return;
    }
    if (request.method == _askQuestionMethod ||
        request.method == _createPlanMethod) {
      _hold(sessionId, upstream, request);
      return;
    }
    _finishOther(sessionId, upstream, request);
  }

  bool _allow(AcpUpstream upstream, AcpClientRequest request) {
    final optionId = preferredAllowOptionId(request.params['options']);
    if (optionId == null) return false;
    upstream.completeClientRequest(request.id, {
      'outcome': 'selected',
      'optionId': optionId,
    });
    return true;
  }

  void _hold(String sessionId, AcpUpstream upstream, AcpClientRequest request) {
    final held = _Held(upstream, request);
    (_held[sessionId] ??= []).add(held);
    _bumpPending(sessionId, 1);
    held.timer = Timer(permissionTimeout, () {
      _settle(sessionId, held, _terminalOutcome(held.request.method));
    });
  }

  void _flushHeld(String sessionId, _PhoneLeg leg) {
    final pending = List<_Held>.from(_held[sessionId] ?? const []);
    for (final held in pending) {
      if (held.settled) continue;
      held.timer?.cancel();
      unawaited(_forwardHeld(sessionId, leg, held));
    }
  }

  Future<void> _forwardHeld(String sessionId, _PhoneLeg leg, _Held held) async {
    if (held.settled) return;
    try {
      final result = await _requestPhone(leg, held.request);
      _settle(sessionId, held, result);
    } on Object {
      if (held.settled) return;
      if (book.connectionFor(sessionId) == null) {
        held.timer = Timer(permissionTimeout, () {
          _settle(sessionId, held, _terminalOutcome(held.request.method));
        });
        return;
      }
      _settle(sessionId, held, _terminalOutcome(held.request.method));
    }
  }

  void _settle(String sessionId, _Held held, Map<String, Object?> result) {
    if (held.settled) return;
    held.settled = true;
    held.timer?.cancel();
    _held[sessionId]?.remove(held);
    _bumpPending(sessionId, -1);
    held.upstream.completeClientRequest(held.request.id, result);
  }

  void _releaseHeld(String sessionId) {
    final pending = _held.remove(sessionId);
    if (pending == null) return;
    for (final held in pending) {
      _settle(sessionId, held, _terminalOutcome(held.request.method));
    }
  }

  void _finishOther(
    String sessionId,
    AcpUpstream upstream,
    AcpClientRequest request,
  ) {
    final update = _cursorNotificationUpdate(request);
    if (update != null) {
      try {
        spool.appendUpdate(sessionId, update);
      } on Object {
        // A session without a spool still must not leave the CLI waiting.
      }
    }
    upstream.completeClientRequest(request.id, _disconnectedResult(request));
  }

  Future<Map<String, Object?>> _requestPhone(
    _PhoneLeg leg,
    AcpClientRequest request,
  ) {
    return leg.connection.connection.sendRequest(
      request.method,
      params: request.params,
      mapResult: (raw) {
        if (raw is Map) return Map<String, Object?>.from(raw);
        return <String, Object?>{};
      },
    );
  }

  Completer<PromptResponse> _waitForStop(String sessionId) {
    final completer = Completer<PromptResponse>();
    (_promptWaiters[sessionId] ??= []).add(completer);
    return completer;
  }

  void _dropWaiter(String sessionId, Completer<PromptResponse> waiter) {
    _promptWaiters[sessionId]?.remove(waiter);
  }

  void _bumpPending(String sessionId, int delta) {
    final next = (_permissionPendingCounts[sessionId] ?? 0) + delta;
    if (next <= 0) {
      _permissionPendingCounts.remove(sessionId);
    } else {
      _permissionPendingCounts[sessionId] = next;
    }
  }

  bool _spoolReady(String sessionId) {
    requireSafeAcpProxySessionId(sessionId);
    final dir = '${spool.root.path}/acp-proxy/sessions/$sessionId';
    return File('$dir/meta.json').existsSync() &&
        File('$dir/updates.jsonl').existsSync();
  }
}

class _ReplayGate {
  final pending = <Map<String, Object?>>[];
  final requests = <AcpClientRequest>[];
}

class _Capture {
  String? sessionId;
  var hold = true;
  var bound = false;
  var ended = false;
  final updates = <Map<String, Object?>>[];
  final requests = <AcpClientRequest>[];
  StreamSubscription<Map<String, Object?>>? updateSub;
  StreamSubscription<AcpClientRequest>? requestSub;

  List<Map<String, Object?>> takeUpdates() {
    final copy = List<Map<String, Object?>>.of(updates);
    updates.clear();
    return copy;
  }

  List<AcpClientRequest> takeRequests() {
    final copy = List<AcpClientRequest>.of(requests);
    requests.clear();
    return copy;
  }

  Future<void> cancel() async {
    if (bound) return;
    final update = updateSub;
    final request = requestSub;
    updateSub = null;
    requestSub = null;
    await update?.cancel();
    await request?.cancel();
  }
}

class _PhoneLeg {
  _PhoneLeg(this.id, this.connection);

  final String id;
  final AgentConnection connection;

  AgentContext get context => connection.agent;
}

class _Held {
  _Held(this.upstream, this.request);

  final AcpUpstream upstream;
  final AcpClientRequest request;
  Timer? timer;
  var settled = false;
}

List<Map<String, Object?>> _mcpMaps(List<McpServer> servers) => [
  for (final server in servers) server.toJson(),
];

String _promptText(PromptRequest request) {
  final buffer = StringBuffer();
  for (final block in request.prompt) {
    if (block is TextContentBlock) buffer.write(block.text);
  }
  return buffer.toString();
}

StopReason _stopReason(Map<String, Object?> update) {
  final raw = update['stopReason'];
  if (raw is! String) return StopReason.endTurn;
  try {
    return StopReason.fromJson(raw);
  } on FormatException {
    return StopReason.endTurn;
  }
}

const _updateTodosMethod = 'cursor/update_todos';
const _taskMethod = 'cursor/task';
const _generateImageMethod = 'cursor/generate_image';

Map<String, Object?> _terminalOutcome(String method) {
  if (method == _permissionMethod) {
    return const {'outcome': 'cancelled'};
  }
  if (method == _askQuestionMethod || method == _createPlanMethod) {
    return _nestedCancelled;
  }
  return const {};
}

Map<String, Object?> _disconnectedResult(AcpClientRequest request) {
  if (_isCursorNotification(request.method)) {
    return _cursorNotificationAck(request.method, request.params);
  }
  return _terminalOutcome(request.method);
}

bool _isCursorNotification(String method) {
  return method == _updateTodosMethod ||
      method == _taskMethod ||
      method == _generateImageMethod;
}

/// Ack cursor-agent already accepts for a notification sent as a request.
Map<String, Object?> _cursorNotificationAck(
  String method,
  Map<String, Object?> params,
) {
  switch (method) {
    case _updateTodosMethod:
      final todos = _todoItems(params['todos']);
      if (todos == null) return _nestedCancelled;
      return {
        'outcome': {'outcome': 'accepted', 'todos': todos},
      };
    case _taskMethod:
      if (_taskUpdate(params) == null) return _nestedCancelled;
      final agentId = _nonEmpty(params['agentId']);
      return {
        'outcome': {
          'outcome': 'completed',
          if (agentId != null) 'agentId': agentId,
          if (params['durationMs'] is num) 'durationMs': params['durationMs'],
        },
      };
    case _generateImageMethod:
      if (_imageUpdate(params) == null) return _nestedCancelled;
      final filePath = _nonEmpty(params['filePath']);
      if (filePath == null) return _nestedCancelled;
      return {
        'outcome': {'outcome': 'generated', 'filePath': filePath},
      };
    default:
      return _nestedCancelled;
  }
}

/// Session update the phone can replay. `{method, params}` is not one.
Map<String, Object?>? _cursorNotificationUpdate(AcpClientRequest request) {
  switch (request.method) {
    case _updateTodosMethod:
      final todos = _todoItems(request.params['todos']);
      if (todos == null) return null;
      return {
        'sessionUpdate': 'tool_call',
        'toolCallId': _nonEmpty(request.params['toolCallId']) ?? 'TodoWrite',
        'title': 'TodoWrite',
        'status': 'completed',
        'kind': 'other',
        'rawInput': {'todos': todos, 'merge': request.params['merge'] == true},
      };
    case _taskMethod:
      return _taskUpdate(request.params);
    case _generateImageMethod:
      return _imageUpdate(request.params);
    default:
      return null;
  }
}

Map<String, Object?>? _taskUpdate(Map<String, Object?> params) {
  final toolCallId = _nonEmpty(params['toolCallId']);
  final description = _nonEmpty(params['description']);
  if (toolCallId == null || description == null) return null;
  final subagent = _cursorSubagentType(params['subagentType']);
  return {
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': (subagent == null || subagent.isEmpty) ? 'task' : subagent,
    'status': 'completed',
    'kind': 'other',
    'rawInput': {
      'description': description,
      if (subagent != null) 'subagentType': subagent,
    },
  };
}

Map<String, Object?>? _imageUpdate(Map<String, Object?> params) {
  final toolCallId = _nonEmpty(params['toolCallId']);
  final description = _nonEmpty(params['description']);
  if (toolCallId == null || description == null) return null;
  final filePath = _nonEmpty(params['filePath']);
  return {
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': 'generate_image',
    'status': 'completed',
    'kind': 'other',
    'rawInput': {
      'description': description,
      if (filePath != null) 'filePath': filePath,
    },
  };
}

List<Map<String, Object?>>? _todoItems(Object? raw) {
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is Map)
        {
          'id': _asString(item['id']),
          'content': _asString(item['content']),
          'status': _asString(item['status']),
        },
  ];
}

String? _cursorSubagentType(Object? raw) {
  if (raw is String) return _nonEmpty(raw);
  if (raw is! Map) return null;
  final custom = raw['custom'];
  if (custom is String) return _nonEmpty(custom);
  for (final value in raw.values) {
    if (value is String) {
      final trimmed = _nonEmpty(value);
      if (trimmed != null) return trimmed;
    }
  }
  return null;
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _asString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

final _nestedCancelled = <String, Object?>{
  'outcome': <String, Object?>{'outcome': 'cancelled'},
};

String _updateKey(Map<String, Object?> update) =>
    jsonEncode(_normalizeMap(update));

Object _surface(Object error) {
  if (error is RpcError) return error;
  if (error is FormatException) {
    return RpcError.fromCode(ErrorCode.invalidParams, data: error.message);
  }
  return RpcError(
    code: ErrorCode.internalError.code,
    message: error.toString(),
  );
}

Future<void> _closeQuiet(AcpUpstream upstream) async {
  try {
    await upstream.close();
  } on Object {
    // The caller still surfaces the original open failure.
  }
}

Map<String, Object?> _normalizeMap(Map<Object?, Object?> raw) {
  final normalized = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key == null) continue;
    normalized[key.toString()] = _normalizeValue(entry.value);
  }
  return normalized;
}

Object? _normalizeValue(Object? value) {
  if (value is Map) {
    return _normalizeMap(Map<Object?, Object?>.from(value));
  }
  if (value is List) {
    return [for (final item in value) _normalizeValue(item)];
  }
  return value;
}
