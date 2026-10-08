import 'dart:async';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import 'agent_presence_projection.dart';
import 'dispatcher.dart';
import 'event_transport_codec.dart';

/// Byte-stream seam for [EventTransportClient]. Task 6 supplies `open()`
/// (advertisement + SSH `forwardLocal`); this type does not import dartssh2.
abstract interface class EventTransportByteChannel {
  Stream<List<int>> get incoming;
  void add(List<int> data);
  Future<void> close();
}

/// SSH-agnostic NDJSON client: subscribe, snapshot, dispatch, reconnect.
///
/// Does not read advertisement files, does not SSH, and does not call
/// `projection.handle` — events go through [Dispatcher.dispatch] only.
final class EventTransportClient {
  EventTransportClient({
    required Dispatcher dispatcher,
    required AgentPresenceProjection presence,
    required List<EventTransportFamilyCodec> codecs,
    required Future<EventTransportByteChannel> Function() open,
    Duration Function(int attempt)? backoff,
    void Function(Object error, StackTrace st)? onError,
  }) : _dispatcher = dispatcher,
       _presence = presence,
       _codecs = {for (final c in codecs) c.family: c},
       _open = open,
       _backoff = backoff ?? _defaultBackoff,
       _onError = onError;

  final Dispatcher _dispatcher;
  final AgentPresenceProjection _presence;
  final Map<String, EventTransportFamilyCodec> _codecs;
  final Future<EventTransportByteChannel> Function() _open;
  final Duration Function(int attempt) _backoff;
  final void Function(Object error, StackTrace st)? _onError;

  var _running = false;
  EventTransportByteChannel? _channel;
  Future<void>? _runLoop;
  Completer<void>? _backoffGate;

  /// attempt 0→1s, 1→2s, 2→4s, 3→8s, 4+→16s, then clamp 30s.
  static Duration _defaultBackoff(int attempt) {
    final seconds = 1 << attempt.clamp(0, 4);
    return Duration(seconds: seconds.clamp(0, 30));
  }

  Future<void> start() async {
    _running = true;
    _runLoop = _run();
  }

  Future<void> stop() async {
    _running = false;
    _wakeupBackoff();
    await _channel?.close();
    await _runLoop;
    _presence.clearAll();
  }

  Future<void> _run() async {
    var attempt = 0;
    while (_running) {
      try {
        final channel = await _open();
        _channel = channel;
        if (!_running) {
          await channel.close();
          break;
        }
        attempt = 0;
        channel.add(
          utf8.encode(
            encodeTransportLine({
              'v': eventTransportProtocolVersion,
              'type': 'subscribe',
              'families': [
                eventTransportFamilyAgentPresence,
                eventTransportFamilySessionLifecycle,
              ],
            }),
          ),
        );
        final buffer = <int>[];
        await for (final chunk in channel.incoming) {
          if (!_running) break;
          buffer.addAll(chunk);
          var oversize = false;
          while (true) {
            final nl = buffer.indexOf(10);
            if (nl < 0) {
              if (buffer.length > eventTransportMaxLineBytes) {
                oversize = true;
              }
              break;
            }
            if (nl > eventTransportMaxLineBytes) {
              oversize = true;
              break;
            }
            final line = utf8.decode(buffer.sublist(0, nl));
            buffer.removeRange(0, nl + 1);
            _onLine(line);
          }
          if (oversize) break;
        }
      } catch (e, st) {
        appLogger.w('[event-transport] client loop', error: e, stackTrace: st);
        _onError?.call(e, st);
      } finally {
        await _channel?.close();
        _channel = null;
      }
      if (!_running) break;
      await _delayBackoff(_backoff(attempt++));
    }
  }

  void _wakeupBackoff() {
    final gate = _backoffGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> _delayBackoff(Duration duration) async {
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

  void _onLine(String line) {
    final decoded = tryDecodeTransportLine(line);
    if (decoded == null) return;
    final type = decoded['type'];
    if (type == 'snapshotBegin' &&
        decoded['family'] == eventTransportFamilyAgentPresence) {
      _presence.clearAll();
      return;
    }
    if (type == 'event') {
      final family = decoded['family'];
      if (family is! String) return;
      final codec = _codecs[family];
      if (codec == null) return;
      final event = codec.decode(decoded);
      if (event != null) _dispatcher.dispatch(event);
      return;
    }
    if (type == 'error') {
      appLogger.w(
        '[event-transport] server error ${decoded['code']}: ${decoded['message']}',
      );
      unawaited(_channel?.close());
    }
  }
}
