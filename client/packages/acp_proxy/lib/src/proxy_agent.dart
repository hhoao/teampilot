import 'dart:async';
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
      agentCapabilities: AgentCapabilities(),
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
    final String sessionId;
    try {
      sessionId = await upstream.openNew(
        meta: meta,
        cwd: request.cwd,
        mcpServers: mcpServers,
      );
    } catch (error) {
      await _closeQuiet(upstream);
      throw _surface(error);
    }

    await _remember(
      sessionId: sessionId,
      meta: meta,
      cwd: request.cwd,
      upstream: upstream,
    );
    await _attach(sessionId, _legFor(connection));
    return NewSessionResponse(sessionId: sessionId);
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
  }) async {
    final existing = upstreams[sessionId];
    if (existing != null && existing.alive) {
      await _attach(sessionId, _legFor(connection));
      await _replay(context, sessionId);
      return const LoadSessionResponse();
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
    try {
      await upstream.openLoad(sessionId: sessionId, cwd: cwd);
    } catch (error) {
      await _closeQuiet(upstream);
      throw _surface(error);
    }
    await _remember(
      sessionId: sessionId,
      meta: launch,
      cwd: cwd,
      upstream: upstream,
    );
    await _attach(sessionId, _legFor(connection));
    await _replay(context, sessionId);
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
    final sessionId = request.sessionId;
    await _stopWatching(sessionId);
    final upstream = upstreams.remove(sessionId);
    _releaseHeld(sessionId, const {'outcome': 'cancelled'});
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
    if (upstream != null) await _closeQuiet(upstream);
    book.finishTurn(sessionId);
    await spool.delete(sessionId);
    _metas.remove(sessionId);
    _sessionLeg.remove(sessionId);
    _sessionIds.remove(sessionId);
    disconnectedSince.remove(sessionId);
    return const CloseSessionResponse();
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
    _watch(sessionId, upstream);
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

  void _watch(String sessionId, AcpUpstream upstream) {
    if (identical(_watched[sessionId], upstream)) return;
    _updateSubs.remove(sessionId)?.cancel();
    _requestSubs.remove(sessionId)?.cancel();
    _watched[sessionId] = upstream;
    _updateSubs[sessionId] = upstream.updates.listen((update) {
      _onUpstreamUpdate(sessionId, update);
    });
    _requestSubs[sessionId] = upstream.clientRequests.listen((request) {
      _onClientRequest(sessionId, upstream, request);
    });
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

  Future<void> _replay(AgentContext context, String sessionId) async {
    final updates = await spool.readAll(sessionId);
    for (final update in updates) {
      if (update['sessionUpdate'] == 'stop') continue;
      _sendUpdate(context, sessionId, update);
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
      _settle(sessionId, held, const {'outcome': 'cancelled'});
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
          _settle(sessionId, held, const {'outcome': 'cancelled'});
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

  void _releaseHeld(String sessionId, Map<String, Object?> result) {
    final pending = _held.remove(sessionId);
    if (pending == null) return;
    for (final held in pending) {
      _settle(sessionId, held, result);
    }
  }

  void _finishOther(
    String sessionId,
    AcpUpstream upstream,
    AcpClientRequest request,
  ) {
    try {
      spool.appendUpdate(sessionId, {
        'method': request.method,
        'params': request.params,
      });
    } on Object {
      // A session without a spool still must not leave the CLI waiting.
    }
    upstream.completeClientRequest(request.id, const {});
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
    return Directory(
      '${spool.root.path}/acp-proxy/sessions/$sessionId',
    ).existsSync();
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

Map<String, Object?> _terminalOutcome(String method) {
  if (method == _permissionMethod ||
      method == _askQuestionMethod ||
      method == _createPlanMethod) {
    return const {'outcome': 'cancelled'};
  }
  return const {};
}

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
