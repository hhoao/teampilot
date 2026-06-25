import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/sse/anthropic_sse_encoder.dart';

class RequestLogEntry {
  RequestLogEntry({
    required this.apiKey,
    required this.path,
    required this.at,
  });

  final String apiKey;
  final String path;
  final DateTime at;

  @override
  String toString() =>
      '[$at] apiKey=$apiKey path=$path';
}

class MockAnthropicServer {
  MockAnthropicServer({required ScenarioRegistry scenarios})
      : _scenarios = scenarios;

  final ScenarioRegistry _scenarios;
  HttpServer? _server;
  final List<RequestLogEntry> _requestLog = [];

  int get port {
    final s = _server;
    if (s == null) {
      throw StateError('MockAnthropicServer not started');
    }
    return s.port;
  }

  Uri get baseUri {
    final s = _server;
    if (s == null) {
      throw StateError('MockAnthropicServer not started');
    }
    return Uri(
      scheme: 'http',
      host: s.address.address,
      port: s.port,
    );
  }

  Uri get messagesUri => baseUri.replace(path: '/v1/messages');

  List<RequestLogEntry> get requestLog => List.unmodifiable(_requestLog);

  Future<void> start({InternetAddress? address}) async {
    if (_server != null) {
      throw StateError('MockAnthropicServer already started');
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
    final buf = StringBuffer('MockAnthropicServer diagnostics\n');
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
    if (request.method != 'POST' || !_isMessagesPath(request.uri.path)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('not found')
        ..close();
      return;
    }

    final apiKey = _parseApiKey(request);
    if (apiKey == null || _scenarios.scenarioFor(apiKey) == null) {
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

    try {
      final turn = _scenarios.nextTurn(apiKey);
      final messageId = 'msg_${DateTime.now().microsecondsSinceEpoch}';
      final sse = AnthropicSseEncoder.encodeTurn(
        messageId: messageId,
        model: model,
        turn: turn,
      );

      _requestLog.add(
        RequestLogEntry(
          apiKey: apiKey,
          path: request.uri.path,
          at: DateTime.now(),
        ),
      );

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write(sse)
        ..close();
    } on StateError catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(e.message)
        ..close();
    }
  }

  static bool _isMessagesPath(String path) {
    return path == '/v1/messages' ||
        path == '/anthropic/v1/messages' ||
        path.endsWith('/v1/messages');
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
