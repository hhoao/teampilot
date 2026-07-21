import 'dart:convert';
import 'dart:io';

import 'package:mock_model_gateway/core/scenario_engine.dart';
import 'package:mock_model_gateway/core/turns.dart';
import 'package:mock_model_gateway/server.dart';
import 'package:test/test.dart';

void main() {
  late HttpClient client;

  setUp(() {
    client = HttpClient();
  });

  tearDown(() {
    client.close(force: true);
  });

  Future<HttpClientResponse> postJson(
    Uri uri, {
    required String apiKey,
    Map<String, Object?> body = const {'model': 'mock-model', 'messages': []},
    bool bearer = true,
  }) async {
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    if (bearer) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    } else {
      req.headers.set('x-api-key', apiKey);
    }
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  test('simple actor completes three text turns on chat completions', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'k': MockScenario(
          turns: [
            TextTurn('r1'),
            TextTurn('r2'),
            TextTurn('r3'),
          ],
        ),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/chat/completions');
    final bodies = <String>[];
    for (var i = 0; i < 3; i++) {
      final resp = await postJson(uri, apiKey: 'k');
      expect(resp.statusCode, 200);
      expect(resp.headers.contentType?.mimeType, 'application/json');
      bodies.add(await resp.transform(utf8.decoder).join());
    }

    expect(bodies[0], contains('r1'));
    expect(bodies[1], contains('r2'));
    expect(bodies[2], contains('r3'));
    expect(server.requestLog, hasLength(3));
    expect(server.requestLog.every((e) => e.apiKey == 'k'), isTrue);
    expect(
      server.requestLog.every((e) => e.path == '/v1/chat/completions'),
      isTrue,
    );
  });

  test('tool round-trip on chat completions returns tool then text', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'k': MockScenario(
          turns: [
            ToolUseTurn(
              id: 'call_1',
              toolRef: 'lookup',
              input: {'q': 'ping'},
            ),
            TextTurn('tool-done'),
          ],
        ),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/chat/completions');

    final toolResp = await postJson(uri, apiKey: 'k');
    expect(toolResp.statusCode, 200);
    final toolBody = await toolResp.transform(utf8.decoder).join();
    expect(toolBody, contains('lookup'));
    expect(toolBody, contains('call_1'));
    expect(toolBody, contains('tool_calls'));

    final textResp = await postJson(
      uri,
      apiKey: 'k',
      body: {
        'model': 'mock-model',
        'messages': [
          {
            'role': 'tool',
            'tool_call_id': 'call_1',
            'content': 'pong',
          },
        ],
      },
    );
    expect(textResp.statusCode, 200);
    final textBody = await textResp.transform(utf8.decoder).join();
    expect(textBody, contains('tool-done'));
    expect(server.requestLog, hasLength(2));
  });

  test('POST /v1/messages returns Anthropic SSE for x-api-key', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'lead': MockScenario(turns: [TextTurn('anthropic-hi')]),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/messages');
    final resp = await postJson(uri, apiKey: 'lead', bearer: false);
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'text/event-stream');
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('anthropic-hi'));
    expect(server.requestLog, hasLength(1));
    expect(server.requestLog.single.path, '/v1/messages');
  });

  test('POST /v1/responses smoke returns JSON text turn', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'codex': MockScenario(turns: [TextTurn('responses-hi')]),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/responses');
    final resp = await postJson(
      uri,
      apiKey: 'codex',
      body: {'model': 'mock-model', 'input': []},
    );
    expect(resp.statusCode, 200);
    expect(resp.headers.contentType?.mimeType, 'application/json');
    final body = await resp.transform(utf8.decoder).join();
    expect(body, contains('responses-hi'));
    expect(body, contains('"object":"response"'));
    expect(server.requestLog, hasLength(1));
    expect(server.requestLog.single.path, '/v1/responses');
  });

  test('unknown api key returns 401', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'k': MockScenario(turns: [TextTurn('x')]),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/chat/completions');
    final resp = await postJson(uri, apiKey: 'unknown');
    expect(resp.statusCode, 401);
    final body = await resp.transform(utf8.decoder).join();
    expect(body, isNotEmpty);
    expect(server.requestLog, isEmpty);
  });

  test('exhausted scenario returns 500', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'once': MockScenario(turns: [TextTurn('only')]),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/chat/completions');

    Future<int> post() async {
      final resp = await postJson(uri, apiKey: 'once');
      await resp.drain<void>();
      return resp.statusCode;
    }

    expect(await post(), 200);
    expect(await post(), 500);
  });

  test('dumpDiagnostics includes request log entries', () async {
    final server = MockModelGatewayServer(
      engine: ScenarioEngine({
        'k': MockScenario(turns: [TextTurn('diag')]),
      }),
    );
    await server.start();
    addTearDown(server.stop);

    final uri = server.baseUri.replace(path: '/v1/chat/completions');
    final resp = await postJson(uri, apiKey: 'k');
    await resp.drain<void>();

    final dump = server.dumpDiagnostics();
    expect(dump, contains('k'));
    expect(dump, contains('/v1/chat/completions'));
  });
}
