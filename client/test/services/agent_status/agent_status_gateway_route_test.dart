import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_http_handler.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../team_bus/support/fake_member_launcher.dart';

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
    gateway.attachAgentStatusHandler(
      AgentStatusHttpHandler(
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

  Future<HttpClientResponse> postAgentStatus({
    String? sessionId,
    String? busToken,
    String? member,
    required Object? body,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${gateway.httpPort}/agent-status');
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    if (sessionId != null) {
      req.headers.set(teammateBusMcpSessionHeader, sessionId);
    }
    if (busToken != null) {
      req.headers.set(teammateBusTokenHeader, busToken);
    }
    if (member != null) {
      req.headers.set(teammateBusMcpMemberHeader, member);
    }
    if (body is String) {
      req.add(utf8.encode(body));
    } else {
      req.add(utf8.encode(jsonEncode(body)));
    }
    return req.close();
  }

  test('POST /agent-status with X-Session + X-Member applies waiting', () async {
    gateway.registerAgentStatusSession(sessionId: 's1');

    final resp = await postAgentStatus(
      sessionId: 's1',
      member: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
      },
    );
    expect(resp.statusCode, HttpStatus.ok);
    await resp.drain<void>();

    expect(cubit.state.sessionHasWaiting('s1'), isTrue);
    expect(
      cubit.state.attentionFor(sessionId: 's1', memberId: 'm1'),
      AgentSeatAttention.waiting,
    );
  });

  test('missing X-Member → 400', () async {
    gateway.registerAgentStatusSession(sessionId: 's1');

    final resp = await postAgentStatus(
      sessionId: 's1',
      body: {'hook_event_name': 'PermissionRequest'},
    );
    expect(resp.statusCode, HttpStatus.badRequest);
    await resp.drain<void>();
    expect(cubit.state.sessionHasWaiting('s1'), isFalse);
  });

  test('unknown session → 400', () async {
    final resp = await postAgentStatus(
      sessionId: 'unknown',
      member: 'm1',
      body: {'hook_event_name': 'PermissionRequest'},
    );
    expect(resp.statusCode, HttpStatus.badRequest);
    await resp.drain<void>();
    expect(cubit.state.sessionHasWaiting('unknown'), isFalse);
  });

  test('status-only register works without TeamBus handler', () async {
    gateway.registerAgentStatusSession(sessionId: 'status-only');

    expect(gateway.isSessionRegistered('status-only'), isFalse);

    final resp = await postAgentStatus(
      sessionId: 'status-only',
      member: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
      },
    );
    expect(resp.statusCode, HttpStatus.ok);
    await resp.drain<void>();
    expect(cubit.state.sessionHasWaiting('status-only'), isTrue);
  });

  test('status-only X-Bus-Token auth without X-Session applies waiting', () async {
    final token = gateway.registerAgentStatusSession(sessionId: 'remote-s1');
    expect(gateway.isSessionRegistered('remote-s1'), isFalse);

    final resp = await postAgentStatus(
      busToken: token,
      member: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
      },
    );
    expect(resp.statusCode, HttpStatus.ok);
    await resp.drain<void>();
    expect(cubit.state.sessionHasWaiting('remote-s1'), isTrue);
  });

  test('TeamBus-registered session can POST /agent-status', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    gateway.register(
      sessionId: 'teambus-sess',
      handler: TeammateBusMcpHandler(bus: bus),
    );

    final resp = await postAgentStatus(
      sessionId: 'teambus-sess',
      member: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
      },
    );
    expect(resp.statusCode, HttpStatus.ok);
    await resp.drain<void>();
    expect(cubit.state.sessionHasWaiting('teambus-sess'), isTrue);

    await gateway.unregister('teambus-sess');
  });

  test('corrupt JSON keeps prior state and returns 200', () async {
    gateway.registerAgentStatusSession(sessionId: 's1');

    final ok = await postAgentStatus(
      sessionId: 's1',
      member: 'm1',
      body: {
        'hook_event_name': 'PermissionRequest',
        'tool_name': 'Bash',
      },
    );
    expect(ok.statusCode, HttpStatus.ok);
    await ok.drain<void>();
    expect(cubit.state.sessionHasWaiting('s1'), isTrue);

    final bad = await postAgentStatus(
      sessionId: 's1',
      member: 'm1',
      body: '{not-json',
    );
    expect(bad.statusCode, HttpStatus.ok);
    final text = await bad.transform(utf8.decoder).join();
    expect(jsonDecode(text), <String, Object?>{});
    expect(cubit.state.sessionHasWaiting('s1'), isTrue);
  });
}
