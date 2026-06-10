// teammate-bus stdio↔HTTP 桥接。
//
// 为什么存在：claude 的 HTTP MCP 传输给单个请求设了写死的 ~6 分钟超时
// （fetch/undici 层，不被 progress 重置、env 也够不着），长阻塞工具
// `wait_for_message` 因此每 6 分钟被 "transport dropped" 掐断、重发、烧 token。
// stdio 传输没有这个超时（唯一上限是应用层 MCP_TOOL_TIMEOUT，我们设成 24h），
// 但 stdio 要求 claude spawn 一个子进程。这个程序就是那个子进程：一个哑管道，
// 把 claude 的 stdio MCP 转发到 app 现有的 loopback HTTP bus，用 Dart HttpClient
// （无响应体超时）扛住长 SSE，于是 `wait_for_message` 能真正阻塞一整场。
//
// 用法：teammate_bus_bridge --member <id> --bus-url http://127.0.0.1:<port>/mcp
//   member / bus-url 也可分别从 TEAMPILOT_MEMBER / TEAMPILOT_BUS_URL 环境变量读。
//
// 线协议：
//   stdin/stdout : 换行分隔的 JSON-RPC（MCP stdio 帧）。
//   → app        : POST <bus-url>，body=原始 JSON-RPC，头 X-Member: <id>。
//   ← app        : application/json（一条响应）或 text/event-stream
//                  （`event: message\ndata: {json}` 事件 + `: ping`/`: open` 注释）。
//
// 纯 dart: 库，无任何 package 依赖 —— 方可 `dart compile exe`。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _memberHeader = 'X-Member';

Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  final member = opts['member'] ?? Platform.environment['TEAMPILOT_MEMBER'] ?? '';
  final busUrlRaw =
      opts['bus-url'] ?? Platform.environment['TEAMPILOT_BUS_URL'] ?? '';
  if (busUrlRaw.isEmpty) {
    stderr.writeln('[bus-bridge] missing --bus-url (or TEAMPILOT_BUS_URL)');
    exit(2);
  }
  final busUrl = Uri.parse(busUrlRaw);

  final bridge = _Bridge(member: member, busUrl: busUrl);
  await bridge.run();
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      final key = a.substring(2);
      final eq = key.indexOf('=');
      if (eq >= 0) {
        out[key.substring(0, eq)] = key.substring(eq + 1);
      } else if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        out[key] = args[++i];
      } else {
        out[key] = 'true';
      }
    }
  }
  return out;
}

class _Bridge {
  _Bridge({required this.member, required this.busUrl});

  final String member;
  final Uri busUrl;

  // 自己的 HttpClient：不设任何响应体超时，进行中的 SSE 流可永久挂住。
  // connectionTimeout 只影响"建立连接"，不掐已建立的流；故意不设。
  final HttpClient _http = HttpClient();

  // 序列化 stdout 写入：多个并发请求的响应不能交错成半行。
  Future<void> _stdoutLock = Future<void>.value();

  // 在途请求：id -> 取消回调（用于 notifications/cancelled → 断开对应 HTTP →
  // app 探知断连 → 解除其阻塞的 wait）。
  final Map<String, void Function()> _inflight = <String, void Function()>{};

  Future<void> run() async {
    _http.idleTimeout = const Duration(hours: 24); // 池化连接的空闲上限，无碍进行中的流。
    final done = Completer<void>();
    stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object e, StackTrace _) =>
              stderr.writeln('[bus-bridge] stdin error: $e'),
          onDone: () => done.complete(),
          cancelOnError: false,
        );
    await done.future; // stdin EOF（claude 退出）→ 结束。
    _http.close(force: true);
  }

  void _onLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      stderr.writeln('[bus-bridge] skip non-JSON stdin line');
      return;
    }

    final method = msg['method'];
    // claude 取消某请求：断开对应在途 HTTP，让 app 那侧的 wait 被解除。
    if (method == 'notifications/cancelled') {
      final reqId = (msg['params'] as Map?)?['requestId'];
      final cancel = _inflight[_idKey(reqId)];
      if (cancel != null) cancel();
      return; // app 对该通知无有用副作用，无需转发。
    }

    final hasId = msg.containsKey('id') && msg['id'] != null;
    // 不 await：长 wait_for_message 不能卡住 stdin 读循环（需并发处理其它请求）。
    unawaited(_forward(trimmed, id: hasId ? msg['id'] : null));
  }

  String _idKey(Object? id) => '$id';

  Future<void> _forward(String body, {required Object? id}) async {
    HttpClientRequest? req;
    var cancelled = false;
    try {
      req = await _http.postUrl(busUrl);
      req.headers.set('content-type', 'application/json; charset=utf-8');
      req.headers.set('accept', 'application/json, text/event-stream');
      if (member.isNotEmpty) req.headers.set(_memberHeader, member);
      req.add(utf8.encode(body));
      final resp = await req.close();

      if (id != null) {
        _inflight[_idKey(id)] = () {
          cancelled = true;
          req?.abort(); // 撕掉这条 HTTP → app 探知断连。
        };
      }

      final ctype = resp.headers.contentType?.value ?? '';
      if (ctype.contains('text/event-stream')) {
        await _pumpSse(resp);
      } else if (resp.statusCode == HttpStatus.accepted) {
        // 202：通知，无响应体，无需回写 stdout。
        await resp.drain<void>();
      } else {
        final text = await resp.transform(utf8.decoder).join();
        if (text.trim().isNotEmpty) _writeOut(text.trim());
      }
    } catch (e) {
      if (cancelled) return; // 主动取消导致的报错，正常。
      stderr.writeln('[bus-bridge] forward failed (id=$id): $e');
      if (id != null) _writeOut(_rpcError(id, 'bus bridge transport error: $e'));
    } finally {
      if (id != null) _inflight.remove(_idKey(id));
    }
  }

  // 解析 SSE：累积缓冲，按事件（`\n\n`）切分，把每个 `data:` 负载原样转发到
  // stdout（既包括最终 JSON-RPC 响应，也包括 notifications/progress；`:` 注释跳过）。
  Future<void> _pumpSse(HttpClientResponse resp) async {
    var buffer = '';
    await for (final chunk in resp.transform(utf8.decoder)) {
      buffer += chunk;
      var idx = buffer.indexOf('\n\n');
      while (idx >= 0) {
        final event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        _emitSseEvent(event);
        idx = buffer.indexOf('\n\n');
      }
    }
    if (buffer.trim().isNotEmpty) _emitSseEvent(buffer);
  }

  void _emitSseEvent(String event) {
    final dataLines = <String>[];
    for (final raw in const LineSplitter().convert(event)) {
      if (raw.startsWith(':')) continue; // 注释（: ping / : open）。
      if (raw.startsWith('data:')) {
        dataLines.add(raw.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return;
    final payload = dataLines.join('\n').trim();
    if (payload.isNotEmpty) _writeOut(payload);
  }

  void _writeOut(String line) {
    _stdoutLock = _stdoutLock.then((_) async {
      stdout.writeln(line);
      await stdout.flush();
    });
  }

  String _rpcError(Object id, String message) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': -32000, 'message': message},
  });
}
