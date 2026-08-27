import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentEventGateway(
      AgentEventGateway.forAttention(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postPromptSubmit({
    required String sessionId,
    required String memberId,
    required String prompt,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${gateway.httpPort}/agent-status');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.headers.set('connection', 'close');
    req.headers.set(teammateBusMcpSessionHeader, sessionId);
    req.headers.set(teammateBusMcpMemberHeader, memberId);
    req.add(
      utf8.encode(
        jsonEncode({
          'hook_event_name': 'UserPromptSubmit',
          'prompt': prompt,
        }),
      ),
    );
    return req.close();
  }

  test('UserPromptSubmit prompt is accepted without direct terminal mutation', () async {
    const sessionId = 'ack-s1';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);
    final resp = await postPromptSubmit(
      sessionId: sessionId,
      memberId: memberId,
      prompt: '1',
    );
    await resp.drain();

    expect(resp.statusCode, 200);
  });
}
