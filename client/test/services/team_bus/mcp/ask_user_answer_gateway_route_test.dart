import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/agent_status/ask_user_answer_pending_store.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late TeammateBusMcpGateway gateway;
  late AskUserAnswerPendingStore store;
  late HttpClient client;

  setUp(() async {
    store = AskUserAnswerPendingStore();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAskUserAnswerStore(store);
    gateway.registerAgentStatusSession(sessionId: 'sess-a');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await gateway.dispose();
  });

  Future<HttpClientResponse> getAskUserAnswer({
    String? sessionId,
    String? member,
    String? requestId,
  }) async {
    final uri = gateway.askUserAnswerEndpoint.replace(
      queryParameters: {
        if (requestId != null) 'request_id': requestId,
      },
    );
    final req = await client.getUrl(uri);
    if (sessionId != null) {
      req.headers.set(teammateBusMcpSessionHeader, sessionId);
    }
    if (member != null) {
      req.headers.set(teammateBusMcpMemberHeader, member);
    }
    return req.close();
  }

  test('GET /ask-user-answer empty → 204', () async {
    final resp = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'req_1',
    );
    expect(resp.statusCode, HttpStatus.noContent);
    await resp.drain<void>();
  });

  test('GET /ask-user-answer after put → 200 JSON then 204', () async {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'req_1',
        answers: [
          ['Label'],
        ],
      ),
    );

    final hit = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'req_1',
    );
    expect(hit.statusCode, HttpStatus.ok);
    final body = jsonDecode(await hit.transform(utf8.decoder).join())
        as Map<String, Object?>;
    expect(body['request_id'], 'req_1');
    expect(body['answers'], [
      ['Label'],
    ]);
    expect(body['reject'], false);

    final miss = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'req_1',
    );
    expect(miss.statusCode, HttpStatus.noContent);
    await miss.drain<void>();
  });

  test('GET /ask-user-answer reject entry → 200 then consume', () async {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'req_1',
        reject: true,
      ),
    );

    final hit = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'req_1',
    );
    expect(hit.statusCode, HttpStatus.ok);
    final body = jsonDecode(await hit.transform(utf8.decoder).join())
        as Map<String, Object?>;
    expect(body['request_id'], 'req_1');
    expect(body['reject'], true);
    expect(body.containsKey('answers'), isFalse);
  });

  test('GET /ask-user-answer permission reply → 200 with permission_reply',
      () async {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'perm-1',
        permissionReply: 'once',
      ),
    );

    final hit = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'perm-1',
    );
    expect(hit.statusCode, HttpStatus.ok);
    final body = jsonDecode(await hit.transform(utf8.decoder).join())
        as Map<String, Object?>;
    expect(body['request_id'], 'perm-1');
    expect(body['permission_reply'], 'once');
    expect(body['reject'], false);
    expect(body.containsKey('answers'), isFalse);

    final miss = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'perm-1',
    );
    expect(miss.statusCode, HttpStatus.noContent);
    await miss.drain<void>();
  });

  test('GET /ask-user-answer without request_id → 204', () async {
    store.put(
      sessionId: 'sess-a',
      memberId: 'member-1',
      entry: const AskUserAnswerPendingEntry(
        requestId: 'req_1',
        answers: [
          ['Label'],
        ],
      ),
    );

    final resp = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
    );
    expect(resp.statusCode, HttpStatus.noContent);
    await resp.drain<void>();

    // Entry still available when polled with request_id.
    final hit = await getAskUserAnswer(
      sessionId: 'sess-a',
      member: 'member-1',
      requestId: 'req_1',
    );
    expect(hit.statusCode, HttpStatus.ok);
    await hit.drain<void>();
  });
}
