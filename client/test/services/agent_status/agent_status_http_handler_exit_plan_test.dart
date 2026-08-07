import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_http_handler.dart';
import 'package:teampilot/services/agent_status/exit_plan_mode_hook_gate.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late ExitPlanModeHookGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = ExitPlanModeHookGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        exitPlanModeHookGate: gate,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postExitPlan({
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
    fail('timed out waiting for ExitPlanMode hook waiter');
  }

  Map<String, Object?> exitPlanBody({
    required String toolUseId,
    required String plan,
  }) {
    return {
      'hook_event_name': 'PreToolUse',
      'tool_name': 'ExitPlanMode',
      'tool_use_id': toolUseId,
      'tool_input': {'plan': plan},
    };
  }

  test('PreToolUse hold → allow → permissionDecision allow', () async {
    const sessionId = 'ep-s1';
    const memberId = 'm1';
    const toolUseId = 'toolu-ep-1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postExitPlan(
      sessionId: sessionId,
      memberId: memberId,
      body: exitPlanBody(toolUseId: toolUseId, plan: '1. Do x.'),
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
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        toolUseId: toolUseId,
        reply: const ExitPlanModeHookReply.allow(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join());
    expect(decoded, isA<Map>());
    final hook = (decoded as Map)['hookSpecificOutput'] as Map;
    expect(hook['permissionDecision'], 'allow');
  });

  test('PreToolUse hold → deny → permissionDecision deny', () async {
    const sessionId = 'ep-s2';
    const memberId = 'm1';
    const toolUseId = 'toolu-ep-2';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postExitPlan(
      sessionId: sessionId,
      memberId: memberId,
      body: exitPlanBody(toolUseId: toolUseId, plan: '1. Do y.'),
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
        reply: const ExitPlanModeHookReply.deny(),
      ),
      isTrue,
    );

    final resp = await responseFuture.timeout(const Duration(seconds: 5));
    expect(resp.statusCode, HttpStatus.ok);
    final decoded = jsonDecode(await resp.transform(utf8.decoder).join());
    final hook = (decoded as Map)['hookSpecificOutput'] as Map;
    expect(hook['permissionDecision'], 'deny');
  });

  test('ExitPlan without gate still returns empty 200 and keeps waiting',
      () async {
    final soloCubit = AgentAttentionCubit(pruneInterval: null);
    addTearDown(soloCubit.close);
    final soloGateway = TeammateBusMcpGateway();
    await soloGateway.ensureStarted();
    addTearDown(soloGateway.dispose);
    soloGateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
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
        jsonEncode(exitPlanBody(toolUseId: 'toolu-x', plan: '1. Do z.')),
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
