import 'dart:convert';
import 'dart:io';

import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/server.dart';
import 'package:test/test.dart';

void main() {
  late MockAnthropicServer server;
  late HttpClient client;

  setUp(() async {
    server = MockAnthropicServer(scenarios: pingPongMixedClaudeScenarios());
    await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('POST /v1/messages routes by x-api-key and returns SSE', () async {
    final req = await client.postUrl(server.messagesUri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', leadScriptApiKey);
    req.add(
      utf8.encode(
        jsonEncode({
          'model': 'mock-model',
          'max_tokens': 1024,
          'messages': [],
        }),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text/event-stream');
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('list_teammates'));
    expect(server.requestLog.length, 1);
    expect(server.requestLog.single.apiKey, leadScriptApiKey);
    expect(server.requestLog.single.path, '/v1/messages');
  });

  test('unknown api key returns 401', () async {
    final req = await client.postUrl(server.messagesUri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', 'unknown-key');
    req.add(
      utf8.encode(
        jsonEncode({
          'model': 'mock-model',
          'max_tokens': 1024,
          'messages': [],
        }),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, 401);
    final body = await resp.transform(utf8.decoder).join();
    expect(body, isNotEmpty);
    expect(server.requestLog, isEmpty);
  });

  test('/anthropic/v1/messages also works', () async {
    final uri = Uri.parse('${server.baseUri}/anthropic/v1/messages');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', workerScriptApiKey);
    req.add(
      utf8.encode(
        jsonEncode({
          'model': 'mock-model',
          'max_tokens': 1024,
          'messages': [],
        }),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, 200);
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('wait_for_message'));
    expect(server.requestLog.length, 1);
    expect(server.requestLog.single.path, '/anthropic/v1/messages');
  });

  test('Authorization Bearer header is accepted', () async {
    final req = await client.postUrl(server.messagesUri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('Authorization', 'Bearer $workerScriptApiKey');
    req.add(
      utf8.encode(
        jsonEncode({
          'model': 'custom-model',
          'max_tokens': 1024,
          'messages': [],
        }),
      ),
    );
    final resp = await req.close();
    expect(resp.statusCode, 200);
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('wait_for_message'));
    expect(body, contains('custom-model'));
  });

  test('exhausted scenario returns 500', () async {
    final reg = ScenarioRegistry({
      'once': MockScenario(turns: [TextTurn('only')]),
    });
    final shortServer = MockAnthropicServer(scenarios: reg);
    await shortServer.start();
    addTearDown(() => shortServer.stop());

    Future<int> post() async {
      final req = await client.postUrl(shortServer.messagesUri);
      req.headers.set('content-type', 'application/json');
      req.headers.set('x-api-key', 'once');
      req.add(utf8.encode(jsonEncode({'model': 'm', 'messages': []})));
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode;
    }

    expect(await post(), 200);
    expect(await post(), 500);
  });

  test('dumpDiagnostics includes request log entries', () async {
    final req = await client.postUrl(server.messagesUri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('x-api-key', leadScriptApiKey);
    req.add(utf8.encode(jsonEncode({'model': 'mock-model', 'messages': []})));
    final resp = await req.close();
    await resp.drain<void>();

    final dump = server.dumpDiagnostics();
    expect(dump, contains(leadScriptApiKey));
    expect(dump, contains('/v1/messages'));
  });
}
