import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/logging/logger.dart';
import '../cancellation.dart';
import 'jsonrpc.dart';
import 'mcp_method.dart';
import 'teammate_bus_mcp_handler.dart';

/// Per-session HTTP/SSE transport for [TeammateBusMcpHandler].
///
/// Owns in-flight `wait_for_message` SSE streams so a gateway can cancel them
/// independently when a session unregisters.
class TeammateBusMcpHttpDelegate {
  TeammateBusMcpHttpDelegate({
    required this.handler,
    this.progressInterval = const Duration(seconds: 20),
  });

  final TeammateBusMcpHandler handler;
  final Duration progressInterval; // < opencode 30s tool timeout

  /// In-flight `_streamLongRunning` cancel handles.
  final Set<CancellationToken> _activeStreams = <CancellationToken>{};

  /// Open SSE `wait_for_message` streams (integration tests observe park).
  int get activeWaitStreamCount => _activeStreams.length;

  /// Cancel every in-flight long-running stream (session unregister / teardown).
  void cancelAllStreams() {
    for (final cancel in _activeStreams.toList()) {
      cancel.cancel();
    }
  }

  Future<void> handleIdleRequest(
    HttpRequest request, {
    required String memberId,
  }) async {
    try {
      await request.drain<void>();
      // Stop-hook only returns CLI decision (block/allow); no bus coordination.
      final reply = memberId.isEmpty
          ? '{}'
          : handler.idleStopDecision(memberId);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        )
        ..write(reply);
      await request.response.close();
      endTurnForIdle(memberId);
    } catch (e, st) {
      appLogger.e(
        '[teammate-bus-mcp] idle request failed',
        error: e,
        stackTrace: st,
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Ends the bus turn for an idle push CLI. No-op for forceWait CLIs: they
  /// are re-directed into `wait_for_message` on `/idle`, and their turn ends
  /// only when they actually park there.
  void endTurnForIdle(String memberId) {
    if (memberId.isNotEmpty && handler.isPushDelivery(memberId)) {
      handler.notifyIdle(memberId);
    }
  }

  Future<void> handleMcpRequest(
    HttpRequest request, {
    required String memberId,
  }) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final rpc = JsonRpcRequest.tryParse(body);
      if (rpc == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      if (rpc.isNotification) {
        await handler.handle(memberId, rpc); // side effects only
        request.response.statusCode = HttpStatus.accepted; // 202
        await request.response.close();
        return;
      }

      if (handler.isLongRunning(rpc)) {
        await _streamLongRunning(request.response, memberId, rpc);
        return;
      }

      final res = await handler.handle(memberId, rpc);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        )
        ..write(res!.encode());
      await request.response.close();
    } catch (e, st) {
      appLogger.e(
        '[teammate-bus-mcp] request failed',
        error: e,
        stackTrace: st,
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _streamLongRunning(
    HttpResponse response,
    String member,
    JsonRpcRequest rpc,
  ) async {
    // Send 200 + SSE headers immediately (satisfies claude 60s first-byte).
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-type', 'text/event-stream; charset=utf-8')
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('connection', 'keep-alive');
    response.write(': open\n\n');
    await response.flush();

    // Client disconnect → cancel blocked wait. Disconnect is detected by
    // keepalive write failure (progressInterval cycle). Also register on
    // _activeStreams so cancelAllStreams() can end the wait deterministically.
    final cancel = CancellationToken();
    _activeStreams.add(cancel);
    handler.waitCancels.register(rpc.id, cancel, memberId: member);

    final progressToken = _progressToken(rpc);
    final sw = Stopwatch()..start();
    var pings = 0;
    var disconnectAtSec = -1;
    appLogger.d(
      '[teammate-bus-mcp] stream open member=$member '
      'tool=${rpc.toolName?.value} id=${rpc.id} '
      'progressToken=${progressToken != null} '
      'interval=${progressInterval.inSeconds}s',
    );
    appLogger.d(
      '[teammate-bus-mcp] request _meta member=$member '
      'id=${rpc.id} _meta=${jsonEncode(rpc.params['_meta'])}',
    );

    final keepalive = Timer.periodic(progressInterval, (timer) async {
      pings++;
      try {
        response.write(': ping\n\n');
        final sentProgress = progressToken != null;
        if (sentProgress) {
          response.write(
            'event: message\ndata: ${jsonEncode({
              'jsonrpc': '2.0',
              'method': McpMethod.notificationsProgress,
              'params': {'progressToken': progressToken, 'progress': 0},
            })}\n\n',
          );
        }
        await response.flush();
      } catch (e) {
        disconnectAtSec = sw.elapsed.inSeconds;
        timer.cancel();
        cancel.cancel();
      }
    });

    try {
      final delivery = await handler.beginWait(member, rpc, cancel: cancel);
      if (cancel.isCancelled) {
        delivery.abort();
        appLogger.i(
          '[teammate-bus-mcp] wait cancelled (client gone) member=$member '
          't=${sw.elapsed.inSeconds}s — no batch consumed',
        );
      } else {
        try {
          response.write(
            'event: message\ndata: ${delivery.response.encode()}\n\n',
          );
          await response.flush();
          if (cancel.isCancelled) {
            delivery.abort();
            appLogger.i(
              '[teammate-bus-mcp] wait superseded/cancelled after take '
              'member=$member t=${sw.elapsed.inSeconds}s — batch re-queued',
            );
          } else {
            await delivery.confirm();
            appLogger.i(
              '[teammate-bus-mcp] stream delivered result member=$member '
              't=${sw.elapsed.inSeconds}s pings=$pings',
            );
          }
        } catch (e) {
          delivery.abort();
          appLogger.w(
            '[teammate-bus-mcp] result write FAILED member=$member '
            't=${sw.elapsed.inSeconds}s — client gone; batch re-queued to the '
            'inbox (not lost), will redeliver on reconnect: $e',
          );
        }
      }
    } finally {
      handler.waitCancels.unregister(rpc.id, memberId: member, cancel: cancel);
      _activeStreams.remove(cancel);
      keepalive.cancel();
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Object? _progressToken(JsonRpcRequest rpc) {
    final meta = rpc.params['_meta'];
    return meta is Map ? meta['progressToken'] : null;
  }
}
