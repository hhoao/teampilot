import 'dart:async';

import '../../utils/logging/logger.dart';
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
import 'session_channel.dart';
import 'session_envelope.dart';
import 'session_frame_codec.dart';
import 'session_models.dart';

typedef SessionSnapshotsHandler =
    void Function(List<SessionSnapshot> snapshots);
typedef SessionDeltaHandler = void Function(SessionDelta delta);
typedef SessionContentHandler =
    void Function(SessionContentInvalidated invalidation);
typedef SessionContentDeltaHandler = void Function(SessionContentDelta delta);
typedef SessionListHandler = void Function(SessionListDelta delta);
typedef SessionAttentionBatchHandler = void Function(AttentionBatch batch);
typedef SessionErrorHandler = void Function(String code, String message);
typedef SessionVoidHandler = void Function();

/// Client-side callbacks. All are optional so tests and narrow consumers only
/// implement the channel they care about.
final class SessionClientCallbacks {
  const SessionClientCallbacks({
    this.onSnapshot,
    this.onDelta,
    this.onContent,
    this.onContentDelta,
    this.onSessionList,
    this.onAttentionBatch,
    this.onError,
    this.onReady,
    this.onClosed,
  });

  final SessionSnapshotsHandler? onSnapshot;
  final SessionDeltaHandler? onDelta;
  final SessionContentHandler? onContent;
  final SessionContentDeltaHandler? onContentDelta;
  final SessionListHandler? onSessionList;
  final SessionAttentionBatchHandler? onAttentionBatch;
  final SessionErrorHandler? onError;
  final SessionVoidHandler? onReady;
  final SessionVoidHandler? onClosed;
}

/// One session-protocol client connection.
///
/// It sends typed intents and dispatches snapshots/deltas/content/attention.
/// Reconnect/backoff lives in [SessionClientConnection].
final class SessionClient {
  SessionClient({
    required SessionByteChannel channel,
    required this.deviceId,
    this.attentionCursors,
    this.callbacks = const SessionClientCallbacks(),
    this.helloTimeout = const Duration(seconds: 5),
    this.intentTimeout = const Duration(seconds: 5),
  }) : _channel = channel;

  final SessionByteChannel _channel;
  final String deviceId;
  final Map<String, AttentionCursor> Function()? attentionCursors;
  final SessionClientCallbacks callbacks;
  final Duration helloTimeout;
  final Duration intentTimeout;

  final SessionFrameDecoder _decoder = SessionFrameDecoder();
  final Completer<void> _done = Completer<void>();
  final Map<String, Completer<SessionIntentResult>> _pending = {};
  final Map<String, Timer> _pendingTimers = {};
  StreamSubscription<List<int>>? _incoming;
  Timer? _helloTimer;
  int _intentSeq = 0;
  int _seq = 0;
  bool _ready = false;
  bool _closed = false;

  int? _epoch;
  String? _authorityId;

  int? get epoch => _epoch;

  String? get authorityId => _authorityId;

  bool get isReady => _ready;

  Future<void> get done => _done.future;

  Future<void> start() async {
    if (_closed) return;
    _incoming = _channel.incoming.listen(
      _onData,
      onDone: () => unawaited(close()),
      onError: (Object error, StackTrace stackTrace) {
        appLogger.w(
          '[session-client] incoming error',
          error: error,
          stackTrace: stackTrace,
        );
        unawaited(close());
      },
      cancelOnError: true,
    );
    _helloTimer = Timer(helloTimeout, () {
      if (_ready) return;
      callbacks.onError?.call('handshake_timeout', 'helloAck not received');
      unawaited(close());
    });
    _send(
      SessionMessageType.hello,
      channel: SessionChannel.control,
      body: {
        'proto': sessionProtocolVersion,
        'device': deviceId,
        'caps': const [
          'state',
          'content.invalidated',
          'intent.turn.cancel',
          'intent.turn.edit',
          'op.state',
          'attention.log.v1',
        ],
        'cursors': {
          for (final entry
              in (attentionCursors?.call() ?? const <String, AttentionCursor>{})
                  .entries)
            entry.key: entry.value.toJson(),
        },
      },
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _helloTimer?.cancel();
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(
          const SessionIntentResult(
            id: '',
            status: SessionIntentStatus.rejected,
            code: 'disconnected',
          ),
        );
      }
    }
    _pending.clear();
    await _incoming?.cancel();
    await _channel.close();
    if (!_done.isCompleted) _done.complete();
    callbacks.onClosed?.call();
  }

  Future<SessionIntentResult> cancelTurn({
    required String sessionId,
    required String memberId,
    String? expectedTurnId,
  }) => _sendIntent(
    op: 'turn.cancel',
    sessionId: sessionId,
    memberId: memberId,
    expectedTurnId: expectedTurnId,
  );

  /// Delegates an edited-message resend to the authority. Resolves once the
  /// operation is queued; phases arrive through the session snapshot/delta.
  Future<SessionIntentResult> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
    String? expectedTurnId,
  }) => _sendIntent(
    op: 'turn.edit',
    sessionId: sessionId,
    memberId: memberId,
    expectedTurnId: expectedTurnId,
    operationId: operationId,
    userMessageId: userMessageId,
    text: text,
  );

  Future<SessionIntentResult> cancelOperation({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) => _sendIntent(
    op: 'op.cancel',
    sessionId: sessionId,
    memberId: memberId,
    operationId: operationId,
  );

  Future<SessionIntentResult> refreshSessions({required String workspaceId}) =>
      _sendIntent(
        op: 'session.refresh',
        sessionId: '',
        memberId: '',
        workspaceId: workspaceId,
      );

  Future<SessionIntentResult> createSession({
    required String workspaceId,
    required String sessionId,
    required Map<String, Object?> entry,
  }) => _sendIntent(
    op: 'session.create',
    sessionId: sessionId,
    memberId: '',
    workspaceId: workspaceId,
    sessionListEntry: entry,
  );

  Future<SessionIntentResult> removeSession({
    required String workspaceId,
    required String sessionId,
  }) => _sendIntent(
    op: 'session.remove',
    sessionId: sessionId,
    memberId: '',
    workspaceId: workspaceId,
  );

  Future<SessionIntentResult> _sendIntent({
    required String op,
    required String sessionId,
    required String memberId,
    String workspaceId = '',
    Map<String, Object?>? sessionListEntry,
    String? expectedTurnId,
    String operationId = '',
    String userMessageId = '',
    String text = '',
  }) async {
    if (_closed) {
      return const SessionIntentResult(
        id: '',
        status: SessionIntentStatus.rejected,
        code: 'disconnected',
      );
    }
    final id = 'intent-${++_intentSeq}';
    final intent = SessionIntent(
      id: id,
      op: op,
      sessionId: sessionId,
      memberId: memberId,
      workspaceId: workspaceId,
      sessionListEntry: sessionListEntry,
      expectedEpoch: _epoch,
      expectedTurnId: expectedTurnId,
      deadline: DateTime.now().toUtc().add(intentTimeout),
      operationId: operationId,
      userMessageId: userMessageId,
      text: text,
    );
    final completer = Completer<SessionIntentResult>();
    _pending[id] = completer;
    _pendingTimers[id] = Timer(intentTimeout, () {
      if (completer.isCompleted) return;
      completer.complete(
        SessionIntentResult(
          id: id,
          status: SessionIntentStatus.expired,
          code: 'timeout',
        ),
      );
      _pending.remove(id);
    });
    _send(
      SessionMessageType.intent,
      channel: SessionChannel.control,
      corr: id,
      body: intent.toJson(),
    );
    final result = await completer.future;
    _pendingTimers.remove(id)?.cancel();
    return result;
  }

  void sendAttach({String? sessionId}) {
    _send(
      SessionMessageType.attach,
      channel: SessionChannel.control,
      body: {
        if (sessionId != null && sessionId.trim().isNotEmpty)
          'sessionId': sessionId.trim(),
      },
    );
  }

  void sendResync() {
    _send(
      SessionMessageType.resync,
      channel: SessionChannel.control,
      body: {'state': true, 'content': true},
    );
  }

  void sendAttentionAck({
    required String authorityId,
    required int epoch,
    required int seq,
  }) {
    _send(
      SessionMessageType.ack,
      channel: SessionChannel.control,
      body: {'authority': authorityId, 'epoch': epoch, 'seq': seq},
    );
  }

  void _onData(List<int> data) {
    for (final envelope in _decoder.add(data)) {
      _onEnvelope(envelope);
    }
    if (_decoder.isBroken) {
      callbacks.onError?.call('protocol', 'frame too large');
      unawaited(close());
    }
  }

  void _onEnvelope(SessionEnvelope envelope) {
    if (_closed) return;
    switch (envelope.type) {
      case SessionMessageType.helloAck:
        _ready = true;
        _helloTimer?.cancel();
        final authority = envelope.body['authority'];
        _authorityId = authority is String ? authority : null;
        final epoch = envelope.body['epoch'];
        _epoch = epoch is num ? epoch.toInt() : null;
        callbacks.onReady?.call();
        break;
      case SessionMessageType.snapshot:
        final raw = envelope.body['sessions'];
        final snapshots = <SessionSnapshot>[];
        if (raw is List) {
          for (final item in raw) {
            final snapshot = SessionSnapshot.fromJson(item);
            if (snapshot != null) snapshots.add(snapshot);
          }
        }
        callbacks.onSnapshot?.call(snapshots);
        break;
      case SessionMessageType.delta:
        final delta = SessionDelta.fromJson(envelope.body);
        if (delta != null) callbacks.onDelta?.call(delta);
        break;
      case SessionMessageType.content:
        final invalidation = SessionContentInvalidated.fromJson(envelope.body);
        if (invalidation != null) callbacks.onContent?.call(invalidation);
        break;
      case SessionMessageType.contentDelta:
        final delta = SessionContentDelta.fromJson(envelope.body);
        if (delta != null) callbacks.onContentDelta?.call(delta);
        break;
      case SessionMessageType.sessionList:
        final delta = SessionListDelta.fromJson(envelope.body);
        if (delta != null) callbacks.onSessionList?.call(delta);
        break;
      case SessionMessageType.events:
        final batch = AttentionBatch.fromJson(envelope.body);
        if (batch != null) callbacks.onAttentionBatch?.call(batch);
        break;
      case SessionMessageType.ack:
        break;
      case SessionMessageType.intentResult:
        final result = SessionIntentResult.fromJson(envelope.body);
        if (result == null) return;
        final key = envelope.corr.isNotEmpty ? envelope.corr : result.id;
        final completer = _pending.remove(key);
        _pendingTimers.remove(key)?.cancel();
        if (completer != null && !completer.isCompleted) {
          completer.complete(result);
        }
        break;
      case SessionMessageType.ping:
        _send(
          SessionMessageType.pong,
          channel: SessionChannel.control,
          corr: envelope.corr,
        );
        break;
      case SessionMessageType.error:
        final code = envelope.body['code'];
        final message = envelope.body['message'];
        callbacks.onError?.call(
          code is String ? code : 'error',
          message is String ? message : '',
        );
        break;
    }
  }

  void _send(
    String type, {
    required SessionChannel channel,
    Map<String, Object?> body = const {},
    String corr = '',
  }) {
    if (_closed) return;
    try {
      _channel.add(
        encodeSessionFrame(
          SessionEnvelope(
            type: type,
            channel: channel,
            seq: ++_seq,
            corr: corr,
            body: body,
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[session-client] write failed',
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(close());
    }
  }
}

/// Reconnecting client wrapper around [SessionClient].
final class SessionClientConnection {
  SessionClientConnection({
    required Future<SessionByteChannel> Function() open,
    required this.deviceId,
    this.attentionCursors,
    this.callbacks = const SessionClientCallbacks(),
    Duration Function(int attempt)? backoff,
    bool Function(Object error)? isExpectedFailure,
    Future<bool> Function(Object error)? waitForRecovery,
  }) : _open = open,
       _backoff = backoff ?? _defaultBackoff,
       _isExpectedFailure = isExpectedFailure,
       _waitForRecovery = waitForRecovery;

  final Future<SessionByteChannel> Function() _open;
  final String deviceId;
  final Map<String, AttentionCursor> Function()? attentionCursors;
  final SessionClientCallbacks callbacks;
  final Duration Function(int attempt) _backoff;
  final bool Function(Object error)? _isExpectedFailure;
  final Future<bool> Function(Object error)? _waitForRecovery;

  SessionClient? _client;
  Future<void>? _loop;
  Completer<void>? _backoffGate;
  Completer<void>? _recoveryGate;
  bool _running = false;

  SessionClient? get client => _client;

  bool get isReady => _client?.isReady ?? false;

  static Duration _defaultBackoff(int attempt) {
    final seconds = 1 << attempt.clamp(0, 4);
    return Duration(seconds: seconds.clamp(0, 30));
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _loop = _run();
  }

  Future<void> stop() async {
    _running = false;
    _wakeupBackoff();
    _wakeupRecovery();
    await _client?.close();
    await _loop;
    _loop = null;
  }

  void _wakeupBackoff() {
    final gate = _backoffGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void _wakeupRecovery() {
    final gate = _recoveryGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _delay(Duration duration) async {
    final gate = Completer<void>();
    _backoffGate = gate;
    final timer = Timer(duration, _wakeupBackoff);
    if (!_running) _wakeupBackoff();
    try {
      await gate.future;
    } finally {
      timer.cancel();
      if (identical(_backoffGate, gate)) _backoffGate = null;
    }
  }

  Future<SessionIntentResult> removeSession({
    required String workspaceId,
    required String sessionId,
  }) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.removeSession(workspaceId: workspaceId, sessionId: sessionId);
  }

  Future<SessionIntentResult> createSession({
    required String workspaceId,
    required String sessionId,
    required Map<String, Object?> entry,
  }) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.createSession(
      workspaceId: workspaceId,
      sessionId: sessionId,
      entry: entry,
    );
  }

  Future<SessionIntentResult> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.editTurn(
      sessionId: sessionId,
      memberId: memberId,
      operationId: operationId,
      userMessageId: userMessageId,
      text: text,
    );
  }

  Future<SessionIntentResult> cancelOperation({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.cancelOperation(
      sessionId: sessionId,
      memberId: memberId,
      operationId: operationId,
    );
  }

  Future<SessionIntentResult> refreshSessions({required String workspaceId}) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.refreshSessions(workspaceId: workspaceId);
  }

  Future<SessionIntentResult> cancelTurn({
    required String sessionId,
    required String memberId,
    String? expectedTurnId,
  }) {
    final client = _client;
    if (client == null || !client.isReady) {
      return Future.value(
        const SessionIntentResult(
          id: '',
          status: SessionIntentStatus.rejected,
          code: 'not_connected',
        ),
      );
    }
    return client.cancelTurn(
      sessionId: sessionId,
      memberId: memberId,
      expectedTurnId: expectedTurnId,
    );
  }

  Future<void> _run() async {
    var attempt = 0;
    while (_running) {
      var waitedForRecovery = false;
      SessionClient? client;
      try {
        final channel = await _open();
        if (!_running) {
          await channel.close();
          break;
        }
        client = SessionClient(
          channel: channel,
          deviceId: deviceId,
          attentionCursors: attentionCursors,
          callbacks: SessionClientCallbacks(
            onSnapshot: callbacks.onSnapshot,
            onDelta: callbacks.onDelta,
            onContent: callbacks.onContent,
            onContentDelta: callbacks.onContentDelta,
            onSessionList: callbacks.onSessionList,
            onAttentionBatch: callbacks.onAttentionBatch,
            onError: callbacks.onError,
            onReady: () {
              attempt = 0;
              callbacks.onReady?.call();
            },
            onClosed: callbacks.onClosed,
          ),
        );
        _client = client;
        await client.start();
        await client.done;
      } on Object catch (error, stackTrace) {
        if (_isExpectedFailure?.call(error) ?? false) {
          appLogger.d(
            '[session-client] waiting for transport: $error',
            error: error,
            stackTrace: stackTrace,
          );
          final wait = _waitForRecovery;
          if (wait != null) {
            waitedForRecovery = await _awaitRecovery(wait, error);
          }
        } else {
          appLogger.w(
            '[session-client] connection failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      } finally {
        _client = null;
        await client?.close();
      }
      if (!_running) break;
      if (waitedForRecovery) {
        attempt = 0;
      } else {
        await _delay(_backoff(attempt++));
      }
    }
  }

  Future<bool> _awaitRecovery(
    Future<bool> Function(Object error) wait,
    Object error,
  ) async {
    final gate = Completer<void>();
    _recoveryGate = gate;
    try {
      return await Future.any([wait(error), gate.future.then((_) => false)]);
    } on Object catch (waitError, waitStack) {
      appLogger.d(
        '[session-client] recovery wait ended: $waitError',
        error: waitError,
        stackTrace: waitStack,
      );
      return false;
    } finally {
      if (identical(_recoveryGate, gate)) _recoveryGate = null;
    }
  }
}
