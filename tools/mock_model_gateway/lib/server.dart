import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_model_gateway/core/scenario_engine.dart';
import 'package:mock_model_gateway/core/tool_name_resolver.dart';
import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/wire/anthropic_messages_adapter.dart';
import 'package:mock_model_gateway/wire/openai_chat_adapter.dart';
import 'package:mock_model_gateway/wire/openai_responses_adapter.dart';
import 'package:mock_model_gateway/wire/wire_adapter.dart';

class RequestLogEntry {
  RequestLogEntry({
    required this.apiKey,
    required this.wire,
    required this.path,
    required this.at,
    required this.turnIndex,
    required this.turnLabel,
  });

  final String apiKey;
  final String wire;
  final String path;
  final DateTime at;

  /// Scripted turn index at dispatch time (0-based).
  final int turnIndex;

  /// Human-readable turn from [ScenarioEngine.describeTurn].
  final String turnLabel;

  @override
  String toString() =>
      '[$at] apiKey=$apiKey wire=$wire turn=$turnIndex ($turnLabel) path=$path';
}

/// Multi-protocol mock model HTTP server (Anthropic / Chat / Responses).
class MockModelGatewayServer {
  MockModelGatewayServer({
    required ScenarioEngine engine,
    List<WireAdapter>? adapters,
  })  : _engine = engine,
        _adapters = List.unmodifiable(
          adapters ??
              [
                AnthropicMessagesAdapter(),
                OpenAiChatAdapter(),
                OpenAiResponsesAdapter(),
              ],
        );

  /// Convenience constructor from actor scenarios + optional tool name map.
  MockModelGatewayServer.scenarios(
    Map<String, MockScenario> scenarios, {
    ToolNameResolver? toolNames,
    List<WireAdapter>? adapters,
  }) : this(
          engine: ScenarioEngine(scenarios, toolNames: toolNames),
          adapters: adapters,
        );

  final ScenarioEngine _engine;
  final List<WireAdapter> _adapters;
  HttpServer? _server;
  final List<RequestLogEntry> _requestLog = [];

  ScenarioEngine get engine => _engine;

  int get port {
    final s = _server;
    if (s == null) {
      throw StateError('MockModelGatewayServer not started');
    }
    return s.port;
  }

  Uri get baseUri {
    final s = _server;
    if (s == null) {
      throw StateError('MockModelGatewayServer not started');
    }
    return Uri(
      scheme: 'http',
      host: s.address.address,
      port: s.port,
    );
  }

  List<RequestLogEntry> get requestLog => List.unmodifiable(_requestLog);

  /// Clears scripted turn indices so the next API call replays from turn 0.
  void resetScenarios() => _engine.reset();

  /// Rewinds one actor's scenario index (see [ScenarioEngine.resetActor]).
  void resetScenario(String apiKey) => _engine.resetActor(apiKey);

  /// Sets the next scripted turn index for [apiKey] without resetting others.
  void seekScenario(String apiKey, int turnIndex) =>
      _engine.seekActor(apiKey, turnIndex);

  /// Number of scripted turns already consumed for [apiKey] (survives resets
  /// of other actors; resets of this actor rewind the index to 0).
  int turnIndexFor(String apiKey) => _engine.peekTurnIndex(apiKey);

  int requestCountFor(String apiKey) =>
      _requestLog
          .where((e) => e.apiKey == apiKey && e.turnIndex >= 0)
          .length;

  Future<void> start({InternetAddress? address}) async {
    if (_server != null) {
      throw StateError('MockModelGatewayServer already started');
    }
    _server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      0,
    );
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
  }

  String dumpDiagnostics() {
    final buf = StringBuffer('MockModelGatewayServer diagnostics\n');
    buf.writeln('baseUri: ${_server == null ? '(stopped)' : baseUri}');
    buf.writeln('requestLog (${_requestLog.length} entries):');
    if (_requestLog.isEmpty) {
      buf.writeln('  (empty)');
    } else {
      for (final entry in _requestLog) {
        buf.writeln('  $entry');
      }
    }
    return buf.toString();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found')
        ..close();
      return;
    }

    final adapter = _adapterFor(request.uri.path);
    if (adapter == null) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found')
        ..close();
      return;
    }

    final apiKey = _parseApiKey(request);
    if (apiKey == null || _engine.scenarioFor(apiKey) == null) {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('unknown api key')
        ..close();
      return;
    }

    final bodyBytes = await request.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final bodyJson = _tryParseJson(bodyBytes);
    final model = bodyJson?['model'] as String? ?? 'mock-model';
    final hasTools = _requestHasTools(bodyJson);
    final streamChat = adapter is OpenAiChatAdapter &&
        OpenAiChatAdapter.wantsStream(bodyJson);

    try {
      // Claude Code / flashskyai issue a tool-less probe before the real
      // tool-bearing turn. Do not consume ScenarioEngine turns for that probe.
      if ((adapter.wireId == 'anthropic' || adapter.wireId == 'openai_chat') &&
          !hasTools) {
        final messageId = 'msg_probe_${DateTime.now().microsecondsSinceEpoch}';
        final body = _encodeAdapterBody(
          adapter: adapter,
          turn: const ResolvedTextTurn(''),
          messageId: messageId,
          model: model,
          streamChat: streamChat,
        );
        _requestLog.add(
          RequestLogEntry(
            apiKey: apiKey,
            wire: adapter.wireId,
            path: request.uri.path,
            at: DateTime.now(),
            turnIndex: -1,
            turnLabel: 'probe(no-tools)',
          ),
        );
        _writeBody(request, adapter: adapter, body: body, streamChat: streamChat);
        return;
      }

      final turnIndex = _engine.peekTurnIndex(apiKey);
      final resolved = _engine.nextResolvedTurn(apiKey);
      // Index was peeked before advance; safe once nextResolvedTurn succeeded.
      final scripted = _engine.scenarioFor(apiKey)!.turns[turnIndex];
      final turn = adapter.resolveInboundTurn(resolved, bodyJson);
      final messageId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
      final body = _encodeAdapterBody(
        adapter: adapter,
        turn: turn,
        messageId: messageId,
        model: model,
        streamChat: streamChat,
      );

      _requestLog.add(
        RequestLogEntry(
          apiKey: apiKey,
          wire: adapter.wireId,
          path: request.uri.path,
          at: DateTime.now(),
          turnIndex: turnIndex,
          turnLabel: ScenarioEngine.describeTurn(scripted),
        ),
      );

      _writeBody(request, adapter: adapter, body: body, streamChat: streamChat);
    } on StateError catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(e.message)
        ..close();
    }
  }

  static bool _requestHasTools(Map<String, Object?>? body) {
    final tools = body?['tools'];
    return tools is List && tools.isNotEmpty;
  }

  static String _encodeAdapterBody({
    required WireAdapter adapter,
    required ResolvedTurn turn,
    required String messageId,
    required String model,
    required bool streamChat,
  }) {
    if (streamChat && adapter is OpenAiChatAdapter) {
      return adapter.encodeStreamingResponse(
        turn: turn,
        messageId: messageId,
        model: model,
      );
    }
    return adapter.encodeResponse(
      turn: turn,
      messageId: messageId,
      model: model,
    );
  }

  static void _writeBody(
    HttpRequest request, {
    required WireAdapter adapter,
    required String body,
    required bool streamChat,
  }) {
    final mimeType =
        streamChat ? 'text/event-stream' : adapter.responseMimeType;
    final mime = mimeType.split('/');
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(mime[0], mime[1])
      ..write(body)
      ..close();
  }

  WireAdapter? _adapterFor(String path) {
    for (final adapter in _adapters) {
      if (adapter.matchesPath(path)) {
        return adapter;
      }
    }
    return null;
  }

  static String? _parseApiKey(HttpRequest request) {
    final headerKey = request.headers.value('x-api-key');
    if (headerKey != null && headerKey.isNotEmpty) {
      return headerKey;
    }

    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null && auth.startsWith('Bearer ')) {
      final key = auth.substring('Bearer '.length).trim();
      if (key.isNotEmpty) {
        return key;
      }
    }

    return null;
  }

  static Map<String, Object?>? _tryParseJson(List<int> bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } on Object {
      // Ignore malformed JSON; scenario routing uses api key only.
    }
    return null;
  }
}
