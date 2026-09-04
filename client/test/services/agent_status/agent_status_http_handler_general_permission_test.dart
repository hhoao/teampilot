import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/general_permission_request_gate.dart';
import 'package:teampilot/services/agent_runtime/agent_event_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late AgentAttentionCubit cubit;
  late GeneralPermissionRequestGate gate;
  late TeammateBusMcpGateway gateway;
  late HttpClient client;

  setUp(() async {
    cubit = AgentAttentionCubit(pruneInterval: null);
    gate = GeneralPermissionRequestGate();
    gateway = TeammateBusMcpGateway();
    await gateway.ensureStarted();
    gateway.attachAgentEventGateway(
      AgentEventGateway.forAttention(
        attention: cubit,
        resolveCli: (_, __) => CliTool.claude,
        resolveSkipPermissions: (_, __) => false,
        generalPermissionGate: gate,
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await cubit.close();
    await gateway.dispose();
  });

  Future<HttpClientResponse> postPermission({
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
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (gate.hasWaiter(sessionId: sessionId, memberId: memberId)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('timed out waiting for general PermissionRequest hook waiter');
  }

  test('allow decision answers the held hook; attention waits then settles',
      () async {
    const sessionId = 'gp-s1';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postPermission(
      sessionId: sessionId,
      memberId: memberId,
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'rm -rf node_modules'},
        'permission_suggestions': [
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
            ],
            'behavior': 'allow',
            'destination': 'localSettings',
          },
        ],
      },
    );
    // The hook is held — the POST stays open until the gate answers.
    await waitUntilWaiter(sessionId: sessionId, memberId: memberId);
    expect(
      cubit.state.entryFor(sessionId: sessionId, memberId: memberId)?.attention,
      AgentSeatAttention.waiting,
    );
    expect(
      gate.complete(
        sessionId: sessionId,
        memberId: memberId,
        reply: GeneralPermissionRequestReply.allow(
          updatedPermissions: [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        ),
      ),
      isTrue,
    );
    final response = await responseFuture.timeout(const Duration(seconds: 5));
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.transform(utf8.decoder).join()), {
      'hookSpecificOutput': {
        'hookEventName': 'PermissionRequest',
        'decision': {
          'behavior': 'allow',
          'updatedPermissions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'rm -rf node_modules'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        },
      },
    });
  });

  test('releaseHold answers {} so the native TUI takes over', () async {
    const sessionId = 'gp-s2';
    const memberId = 'm1';
    gateway.registerAgentStatusSession(sessionId: sessionId);

    final responseFuture = postPermission(
      sessionId: sessionId,
      memberId: memberId,
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
        'tool_input': {'command': 'ls'},
      },
    );
    await waitUntilWaiter(sessionId: sessionId, memberId: memberId);
    expect(
      gate.releaseHold(sessionId: sessionId, memberId: memberId),
      isTrue,
    );
    final response = await responseFuture.timeout(const Duration(seconds: 5));
    expect(response.statusCode, 200);
    expect(
      jsonDecode(await response.transform(utf8.decoder).join()),
      isEmpty,
    );
  });
}
