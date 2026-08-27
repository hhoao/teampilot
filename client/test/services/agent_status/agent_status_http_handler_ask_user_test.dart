import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/agent_status/ask_user_question.dart';
import 'package:teampilot/services/agent_status/ask_user_question_hook_gate.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late AskUserQuestionHookGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = AskUserQuestionHookGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentEventGateway(
      AgentEventGateway.forAttention(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        askUserHookGate: gate,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postAskPreToolUse({
    required String sessionId,
    required String memberId,
    required Map<String, Object?> body,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${gateway.httpPort}/agent-status');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, sessionId);
    req.headers.set(teammateBusMcpMemberHeader, memberId);
    req.add(utf8.encode(jsonEncode(body)));
    return req.close();
  }

  Future<void> waitUntilWaiter({
    required String sessionId,
    required String memberId,
    required String toolUseId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (gate.hasWaiter(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('timed out waiting for AskUserQuestion hook waiter');
  }

  Map<String, Object?> askBody({
    required String toolUseId,
    required List<Map<String, Object?>> questions,
  }) {
    return {
      'hook_event_name': 'PreToolUse',
      'tool_name': 'AskUserQuestion',
      'tool_use_id': toolUseId,
      'tool_input': {'questions': questions},
    };
  }

  test(
    'PreToolUse hold → allow complete → updatedInput.answers',
    () async {
      const sessionId = 'ask-s1';
      const memberId = 'm1';
      const toolUseId = 'toolu-ask-1';
      gateway.registerAgentStatusSession(sessionId: sessionId);

      final questions = const [
        AgentAskUserQuestion(
          question: 'Pick color?',
          options: [
            AgentAskUserOption(label: 'Red'),
            AgentAskUserOption(label: 'Blue'),
          ],
        ),
        AgentAskUserQuestion(
          question: 'Pick size?',
          options: [
            AgentAskUserOption(label: 'S'),
            AgentAskUserOption(label: 'L'),
          ],
        ),
      ];

      final responseFuture = postAskPreToolUse(
        sessionId: sessionId,
        memberId: memberId,
        body: askBody(
          toolUseId: toolUseId,
          questions: [
            {
              'question': 'Pick color?',
              'options': ['Red', 'Blue'],
            },
            {
              'question': 'Pick size?',
              'options': ['S', 'L'],
            },
          ],
        ),
      );

      await waitUntilWaiter(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
      );
      expect(
        cubit.state.attentionFor(sessionId: sessionId, memberId: memberId),
        AgentSeatAttention.waiting,
      );
      expect(
        cubit.state
            .entryFor(sessionId: sessionId, memberId: memberId)
            ?.lastEvent
            ?.askUserQuestions,
        hasLength(2),
      );

      expect(
        gate.complete(
          sessionId: sessionId,
          memberId: memberId,
          toolUseId: toolUseId,
          reply: AskUserQuestionHookReply.allow(
            questions: questions,
            answers: const {
              'Pick color?': 'Blue',
              'Pick size?': 'L',
            },
          ),
        ),
        isTrue,
      );

      final resp = await responseFuture.timeout(const Duration(seconds: 5));
      expect(resp.statusCode, HttpStatus.ok);
      final decoded = jsonDecode(await resp.transform(utf8.decoder).join());
      expect(decoded, isA<Map>());
      final hook = (decoded as Map)['hookSpecificOutput'] as Map;
      expect(hook['permissionDecision'], 'allow');
      final updated = hook['updatedInput'] as Map;
      expect(updated['answers'], {
        'Pick color?': 'Blue',
        'Pick size?': 'L',
      });
      expect(updated['questions'], isA<List>());
      expect((updated['questions'] as List), hasLength(2));
    },
  );

  test('PreToolUse hold → reject → permissionDecision deny', () async {
    const sessionId = 'ask-s2';
    const memberId = 'm1';
    const toolUseId = 'toolu-ask-2';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postAskPreToolUse(
      sessionId: sessionId,
      memberId: memberId,
      body: askBody(
        toolUseId: toolUseId,
        questions: [
          {
            'question': 'OK?',
            'options': ['Yes', 'No'],
          },
        ],
      ),
    );

    await waitUntilWaiter(
      sessionId: sessionId,
      memberId: memberId,
      toolUseId: toolUseId,
    );

    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
        reply: const AskUserQuestionHookReply.reject(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join()) as Map;
    final hook = decoded['hookSpecificOutput'] as Map;
    expect(hook['permissionDecision'], 'deny');
    expect(hook.containsKey('updatedInput'), isFalse);
  });

  test('Ask PreToolUse without gate still returns empty 200', () async {
    final soloCubit = AgentAttentionCubit(pruneInterval: null);
    addTearDown(soloCubit.close);
    final soloGateway = TeammateBusMcpGateway();
    await soloGateway.ensureStarted();
    addTearDown(soloGateway.dispose);
    soloGateway.attachAgentEventGateway(
      AgentEventGateway.forAttention(
        attention: soloCubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
      ),
    );
    soloGateway.registerAgentStatusSession(sessionId: 'no-gate');

    final uri = Uri.parse(
      'http://127.0.0.1:${soloGateway.httpPort}/agent-status',
    );
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, 'no-gate');
    req.headers.set(teammateBusMcpMemberHeader, 'm1');
    req.add(
      utf8.encode(
        jsonEncode(
          askBody(
            toolUseId: 'toolu-x',
            questions: [
              {
                'question': 'OK?',
                'options': ['Yes'],
              },
            ],
          ),
        ),
      ),
    );
    final resp = await req.close().timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final text = await resp.transform(utf8.decoder).join();
    expect(jsonDecode(text), <String, Object?>{});
    expect(
      soloCubit.state.attentionFor(sessionId: 'no-gate', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });
}
