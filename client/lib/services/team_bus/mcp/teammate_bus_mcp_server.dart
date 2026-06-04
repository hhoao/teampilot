import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../utils/logger.dart';
import '../cancellation.dart';
import 'jsonrpc.dart';
import 'teammate_bus_mcp_handler.dart';

/// loopback HTTP（Streamable HTTP 传输）暴露 [TeammateBusMcpHandler]。
class TeammateBusMcpServer {
  TeammateBusMcpServer({
    required this.handler,
    this.progressInterval = const Duration(seconds: 20),
  });

  final TeammateBusMcpHandler handler;
  final Duration progressInterval; // < opencode 30s tool timeout

  HttpServer? _server;
  int get port => _server!.port;
  Uri get endpoint => Uri.parse('http://127.0.0.1:$port/mcp');
  Uri get idleEndpoint => Uri.parse('http://127.0.0.1:$port/idle');

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_onRequest);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (request.method == 'POST' && request.uri.path == '/idle') {
        final member = request.headers.value('x-member')?.trim() ?? '';
        final body = await utf8.decoder.bind(request).join();
        if (member.isNotEmpty) handler.notifyIdle(member);
        // 回 Stop-hook decision：把成员推回 wait_for_message（除非这次是再入的
        // stop，stop_hook_active 为真则放行,防死循环）。
        final reply = member.isEmpty
            ? '{}'
            : handler.stopHookResponse(stopHookActive: _stopHookActive(body));
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType(
            'application',
            'json',
            charset: 'utf-8',
          )
          ..write(reply);
        await request.response.close();
        return;
      }
      if (request.method != 'POST' || request.uri.path != '/mcp') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final member = request.headers.value('x-member')?.trim() ?? '';
      final body = await utf8.decoder.bind(request).join();
      final rpc = JsonRpcRequest.tryParse(body);
      if (rpc == null) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      if (rpc.isNotification) {
        await handler.handle(member, rpc); // side effects only
        request.response.statusCode = HttpStatus.accepted; // 202
        await request.response.close();
        return;
      }

      if (handler.isLongRunning(rpc)) {
        await _streamLongRunning(request.response, member, rpc);
        return;
      }

      final res = await handler.handle(member, rpc);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
        ..write(res!.encode());
      await request.response.close();
    } catch (e, st) {
      appLogger.e('[teammate-bus-mcp] request failed', error: e, stackTrace: st);
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
    // 立即发 200 + SSE 头（满足 claude 60s first-byte）。
    response
      ..statusCode = HttpStatus.ok
      ..headers.set('content-type', 'text/event-stream; charset=utf-8')
      ..headers.set('cache-control', 'no-cache')
      ..headers.set('connection', 'keep-alive');
    response.write(': open\n\n');
    await response.flush();

    // 客户端断连 → 取消阻塞中的 wait，避免 park 永挂、Future 泄漏。断连由下方
    // keepalive 的写失败探知（progressInterval 周期），随后 cancel 解除阻塞。
    final cancel = CancellationToken();

    final progressToken = _progressToken(rpc);
    // 诊断：坐实 leader(claude) 的 wait_for_message 为何会断 —— 记录开流、每次
    // keepalive 的耗时、keepalive 写失败(=客户端断开)的精确秒数、以及结果是否
    // 写得回去。Stopwatch 避免依赖墙钟。
    final sw = Stopwatch()..start();
    var pings = 0;
    var disconnectAtSec = -1;
    appLogger.i(
      '[teammate-bus-mcp] stream open member=$member '
      'tool=${rpc.params['name']} id=${rpc.id} '
      'progressToken=${progressToken != null} '
      'interval=${progressInterval.inSeconds}s',
    );

    final keepalive = Timer.periodic(progressInterval, (timer) async {
      pings++;
      try {
        // 注释保活（保 TCP）+ progress（为 opencode 续 30s 超时）。
        response.write(': ping\n\n');
        if (progressToken != null) {
          response.write(
            'event: message\ndata: ${jsonEncode({
              'jsonrpc': '2.0',
              'method': 'notifications/progress',
              'params': {'progressToken': progressToken, 'progress': 0},
            })}\n\n',
          );
        }
        await response.flush();
        appLogger.d(
          '[teammate-bus-mcp] keepalive #$pings member=$member '
          't=${sw.elapsed.inSeconds}s',
        );
      } catch (e) {
        disconnectAtSec = sw.elapsed.inSeconds;
        appLogger.w(
          '[teammate-bus-mcp] keepalive write FAILED member=$member '
          'after ${disconnectAtSec}s (#$pings pings, progressToken='
          '${progressToken != null}) — client dropped the SSE: $e',
        );
        timer.cancel();
        cancel.cancel(); // 解除阻塞中的 wait，member 不再永卡 park
      }
    });

    try {
      // 抽干信箱但不标记已读：写回成功 → confirm(标记已读)；失败 → abort(放回信箱)。
      final delivery = await handler.beginWait(member, rpc, cancel: cancel);
      if (cancel.isCancelled) {
        // 断连解除的等待：batch 必为空（无消息被消费），无需写回 / 回滚。
        delivery.abort();
        appLogger.i(
          '[teammate-bus-mcp] wait cancelled (client gone) member=$member '
          't=${sw.elapsed.inSeconds}s — no batch consumed',
        );
      } else {
        try {
          response
              .write('event: message\ndata: ${delivery.response.encode()}\n\n');
          await response.flush();
          await delivery.confirm();
          appLogger.i(
            '[teammate-bus-mcp] stream delivered result member=$member '
            't=${sw.elapsed.inSeconds}s pings=$pings',
          );
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
      keepalive.cancel();
      appLogger.i(
        '[teammate-bus-mcp] stream closed member=$member '
        'total=${sw.elapsed.inSeconds}s pings=$pings '
        'disconnectAt=${disconnectAtSec < 0 ? 'n/a' : '${disconnectAtSec}s'}',
      );
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Object? _progressToken(JsonRpcRequest rpc) {
    final meta = rpc.params['_meta'];
    return meta is Map ? meta['progressToken'] : null;
  }

  /// Stop hook 输入里的 `stop_hook_active`：CLI 在「已被 Stop hook 拦过一次仍想停」
  /// 时置真。用来一次性放行,避免 Stop→block 死循环。
  bool _stopHookActive(String body) {
    if (body.trim().isEmpty) return false;
    try {
      final json = jsonDecode(body);
      return json is Map && json['stop_hook_active'] == true;
    } catch (_) {
      return false;
    }
  }
}
