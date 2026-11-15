import 'dart:async';

import '../../utils/logging/logger.dart';
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
import '../attention/attention_event.dart';
import 'session_authority.dart';
import 'session_channel.dart';
import 'session_envelope.dart';
import 'session_frame_codec.dart';
import 'session_models.dart';

/// Serves one session-protocol connection (one client).
///
/// `services/session_protocol/` does not know about ChatCubit; the authority is
/// injected and control goes through its [SessionControlPort].
final class SessionServer {
  SessionServer({
    required SessionByteChannel channel,
    required SessionAuthority authority,
    required this.deviceId,
    this.capabilities = const [
      'state',
      'content.invalidated',
      'intent.turn.cancel',
      'intent.turn.edit',
      'op.state',
      'attention.log.v1',
    ],
    this.helloTimeout = const Duration(seconds: 5),
  }) : _channel = channel,
       _authority = authority;

  final SessionByteChannel _channel;
  final SessionAuthority _authority;
  final String deviceId;
  final List<String> capabilities;
  final Duration helloTimeout;

  final SessionFrameDecoder _decoder = SessionFrameDecoder();
  StreamSubscription<List<int>>? _incoming;
  StreamSubscription<SessionDelta>? _deltaSub;
  StreamSubscription<SessionContentInvalidated>? _contentSub;
  StreamSubscription<SessionContentDelta>? _contentDeltaSub;
  StreamSubscription<SessionListDelta>? _sessionListSub;
  StreamSubscription<AttentionEvent>? _attentionSub;
  final List<AttentionEvent> _pendingLiveAttention = [];
  bool _attentionBacklogDone = false;
  int _lastSentAttentionSeq = 0;
  Timer? _helloTimer;
  final Completer<void> _done = Completer<void>();
  bool _started = false;
  bool _helloReceived = false;
  bool _closed = false;
  int _seq = 0;

  Future<void> get done => _done.future;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _incoming = _channel.incoming.listen(
      _onData,
      onDone: _close,
      onError: (Object error, StackTrace stackTrace) {
        appLogger.w(
          '[session-server] incoming error',
          error: error,
          stackTrace: stackTrace,
        );
        _close();
      },
      cancelOnError: true,
    );
    _helloTimer = Timer(helloTimeout, () {
      if (!_helloReceived) {
        _sendError('handshake_timeout', 'hello was not received');
        unawaited(_close());
      }
    });
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _helloTimer?.cancel();
    await _deltaSub?.cancel();
    await _contentSub?.cancel();
    await _contentDeltaSub?.cancel();
    await _sessionListSub?.cancel();
    await _attentionSub?.cancel();
    await _incoming?.cancel();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> stop() async {
    await _close();
    await _channel.close();
  }

  void _onData(List<int> data) {
    for (final envelope in _decoder.add(data)) {
      _onEnvelope(envelope);
    }
    if (_decoder.isBroken) {
      _sendError('protocol', 'frame too large');
      unawaited(_close());
    }
  }

  void _onEnvelope(SessionEnvelope envelope) {
    if (_closed) return;
    if (!_helloReceived) {
      if (envelope.type != SessionMessageType.hello) {
        _sendError('hello_required', 'first message must be hello');
        unawaited(_close());
        return;
      }
      _helloReceived = true;
      _helloTimer?.cancel();
      final rawCursors = envelope.body['cursors'];
      AttentionCursor? cursor;
      if (rawCursors is Map) {
        cursor = AttentionCursor.fromJson(rawCursors[_authority.authorityId]);
      }
      if (cursor != null && cursor.epoch != _authority.epoch) {
        cursor = null;
      }
      _send(
        SessionMessageType.helloAck,
        channel: SessionChannel.control,
        body: {
          'proto': sessionProtocolVersion,
          'authority': _authority.authorityId,
          'epoch': _authority.epoch,
          'device': deviceId,
          'caps': capabilities,
          'earliestSeq': _authority.attentionLog.earliestSeq,
          'latestSeq': _authority.attentionLog.latestSeq,
        },
      );
      _sendSnapshot(_authority.snapshots());
      _subscribeAuthority(cursor);
      return;
    }
    switch (envelope.type) {
      case SessionMessageType.attach:
        _sendSnapshotFor(envelope.body);
        break;
      case SessionMessageType.resync:
        _sendSnapshot(_authority.snapshots());
        break;
      case SessionMessageType.intent:
        unawaited(_handleIntent(envelope));
        break;
      case SessionMessageType.ack:
        break;
      case SessionMessageType.ping:
        _send(
          SessionMessageType.pong,
          channel: SessionChannel.control,
          corr: envelope.corr,
        );
        break;
      case SessionMessageType.hello:
        _sendError('already_hello', 'hello was already received');
        break;
      case SessionMessageType.error:
        appLogger.w(
          '[session-server] client error: ${envelope.body['message']}',
        );
        break;
      default:
        if (envelope.channel == SessionChannel.control) {
          _sendError('unsupported_type', envelope.type);
        }
    }
  }

  Future<void> _handleIntent(SessionEnvelope envelope) async {
    final intent = SessionIntent.fromJson(envelope.body);
    if (intent == null) {
      _sendError('bad_intent', 'intent payload is invalid');
      return;
    }
    final result = await _authority.handleIntent(intent);
    _send(
      SessionMessageType.intentResult,
      channel: SessionChannel.control,
      corr: envelope.corr.isEmpty ? intent.id : envelope.corr,
      body: result.toJson(),
    );
  }

  void _subscribeAuthority(AttentionCursor? cursor) {
    _deltaSub = _authority.deltas.listen(
      (delta) => _send(
        SessionMessageType.delta,
        channel: SessionChannel.state,
        body: delta.toJson(),
      ),
    );
    _contentSub = _authority.content.listen(
      (event) => _send(
        SessionMessageType.content,
        channel: SessionChannel.content,
        body: event.toJson(),
      ),
    );
    _contentDeltaSub = _authority.contentDeltas.listen(
      (event) => _send(
        SessionMessageType.contentDelta,
        channel: SessionChannel.content,
        body: event.toJson(),
      ),
    );
    _sessionListSub = _authority.sessionLists.listen(
      (event) => _send(
        SessionMessageType.sessionList,
        channel: SessionChannel.state,
        body: event.toJson(),
      ),
    );
    _startAttention(cursor);
  }

  void _startAttention(AttentionCursor? cursor) {
    if (cursor == null) {
      _lastSentAttentionSeq = _authority.attentionLog.latestSeq;
      _attentionBacklogDone = true;
    } else {
      _lastSentAttentionSeq = cursor.seq;
    }
    _attentionSub = _authority.attention.listen((event) {
      if (!_attentionBacklogDone) {
        _pendingLiveAttention.add(event);
        return;
      }
      _sendAttentionEvent(event);
    });
    if (cursor != null) {
      unawaited(_sendAttentionBacklog(cursor));
    }
  }

  // Leave headroom for frame/JSON envelope overhead below the codec limit.
  static const int _maxAttentionFrameBytes = sessionMaxFrameBytes - 4096;

  Future<void> _sendAttentionBacklog(AttentionCursor cursor) async {
    var next = cursor;
    while (!_closed) {
      final slice = _authority.attentionLog.slice(cursor: next, limit: 200);
      if (slice.events.isEmpty) {
        if (slice.gap) _sendAttentionBatch(slice);
        break;
      }
      final batches = _splitAttentionSlice(slice);
      for (final batch in batches) {
        if (_closed) break;
        _sendAttentionBatch(batch);
        if (batch.toSeq > next.seq) {
          next = AttentionCursor(
            authorityId: batch.authorityId,
            epoch: batch.epoch,
            seq: batch.toSeq,
          );
        }
      }
      if (slice.events.length < 200) break;
    }
    _attentionBacklogDone = true;
    final pending = List<AttentionEvent>.of(_pendingLiveAttention)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    _pendingLiveAttention.clear();
    for (final event in pending) {
      if (event.seq > _lastSentAttentionSeq) _sendAttentionEvent(event);
    }
  }

  List<AttentionBatch> _splitAttentionSlice(AttentionBatch slice) {
    final out = <AttentionBatch>[];
    var chunk = <AttentionEvent>[];
    for (final event in slice.events) {
      final candidate = [...chunk, event];
      final batch = AttentionBatch(
        authorityId: slice.authorityId,
        epoch: slice.epoch,
        fromSeq: candidate.first.seq,
        toSeq: candidate.last.seq,
        events: candidate,
        gap: chunk.isEmpty && slice.gap,
      );
      if (_encodedEventsSize(batch) <= _maxAttentionFrameBytes) {
        chunk = candidate;
        continue;
      }
      if (chunk.isNotEmpty) {
        out.add(
          AttentionBatch(
            authorityId: slice.authorityId,
            epoch: slice.epoch,
            fromSeq: chunk.first.seq,
            toSeq: chunk.last.seq,
            events: List<AttentionEvent>.unmodifiable(chunk),
            gap: slice.gap && out.isEmpty,
          ),
        );
        chunk = [event];
        final single = AttentionBatch(
          authorityId: slice.authorityId,
          epoch: slice.epoch,
          fromSeq: event.seq,
          toSeq: event.seq,
          events: [event],
        );
        if (_encodedEventsSize(single) > _maxAttentionFrameBytes) {
          // Oversized single event: skip it to avoid an endless reconnect loop
          // on the same cursor. The cursor advances past it in the backlog.
          appLogger.w(
            '[session-server] skipping oversized attention event '
            'authority=${event.authorityId} epoch=${event.epoch} seq=${event.seq}',
          );
          chunk = [];
        }
      } else {
        appLogger.w(
          '[session-server] skipping oversized attention event '
          'authority=${event.authorityId} epoch=${event.epoch} seq=${event.seq}',
        );
      }
    }
    if (chunk.isNotEmpty) {
      out.add(
        AttentionBatch(
          authorityId: slice.authorityId,
          epoch: slice.epoch,
          fromSeq: chunk.first.seq,
          toSeq: chunk.last.seq,
          events: List<AttentionEvent>.unmodifiable(chunk),
          gap: slice.gap && out.isEmpty,
        ),
      );
    } else if (out.isEmpty && slice.gap) {
      out.add(slice);
    }
    return out;
  }

  int _encodedEventsSize(AttentionBatch batch) {
    // Use a stable seq so size measurement is deterministic.
    return encodeSessionFrame(
      SessionEnvelope(
        type: SessionMessageType.events,
        channel: SessionChannel.events,
        seq: 1,
        body: batch.toJson(),
      ),
    ).length;
  }

  void _sendAttentionBatch(AttentionBatch batch) {
    _send(
      SessionMessageType.events,
      channel: SessionChannel.events,
      body: batch.toJson(),
    );
    if (batch.toSeq > _lastSentAttentionSeq) {
      _lastSentAttentionSeq = batch.toSeq;
    }
  }

  void _sendAttentionEvent(AttentionEvent event) {
    if (event.seq <= _lastSentAttentionSeq) return;
    _sendAttentionBatch(
      AttentionBatch(
        authorityId: event.authorityId,
        epoch: event.epoch,
        fromSeq: event.seq,
        toSeq: event.seq,
        events: [event],
      ),
    );
  }

  void _sendSnapshotFor(Map<String, Object?> body) {
    final sessionId = body['sessionId'];
    if (sessionId is! String || sessionId.trim().isEmpty) {
      _sendSnapshot(_authority.snapshots());
      return;
    }
    final snapshot = _authority.snapshot(sessionId.trim());
    _sendSnapshot([if (snapshot != null) snapshot]);
  }

  void _sendSnapshot(List<SessionSnapshot> snapshots) {
    _send(
      SessionMessageType.snapshot,
      channel: SessionChannel.state,
      body: {
        'sessions': [for (final snapshot in snapshots) snapshot.toJson()],
      },
    );
  }

  void _sendError(String code, String message) {
    _send(
      SessionMessageType.error,
      channel: SessionChannel.control,
      body: {'code': code, 'message': message},
    );
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
        '[session-server] write failed',
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(_close());
    }
  }
}
