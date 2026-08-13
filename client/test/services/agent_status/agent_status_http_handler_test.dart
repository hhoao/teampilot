import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_status_http_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/terminal/prompt_submit_ack_tracker.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  late AgentAttentionCubit cubit;
  late PromptSubmitAckTracker tracker;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    tracker = PromptSubmitAckTracker();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        promptAckTracker: tracker,
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

  test('UserPromptSubmit prompt completes tracker pending (acked)', () async {
    const sessionId = 'ack-s1';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);
    final pending = tracker.register(
      sessionId: sessionId,
      memberId: memberId,
      text: '1',
    );

    final resp = await postPromptSubmit(
      sessionId: sessionId,
      memberId: memberId,
      prompt: '1',
    );
    await resp.drain();

    expect(resp.statusCode, 200);
    expect(tracker.isAcked(sessionId: sessionId, memberId: memberId), isTrue);
    expect(await pending, isTrue);
  });
}
