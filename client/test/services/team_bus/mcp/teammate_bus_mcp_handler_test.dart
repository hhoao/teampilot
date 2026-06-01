import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../support/fake_member_launcher.dart';

TeammateBusMcpHandler _handler() =>
    TeammateBusMcpHandler(bus: TeamBus(launcher: FakeMemberLauncher()));

void main() {
  test('initialize advertises tools capability and fixed protocol version', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 0, method: 'initialize'),
    );
    expect(res!.result!['protocolVersion'], '2025-06-18');
    expect(res.result!['capabilities'], {'tools': <String, Object?>{}});
    expect((res.result!['serverInfo'] as Map)['name'], isNotEmpty);
  });

  test('notifications/initialized returns null (202, no body)', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(method: 'notifications/initialized'),
    );
    expect(res, isNull);
  });

  test('tools/list returns the four bus tools', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 1, method: 'tools/list'),
    );
    final names = [
      for (final t in res!.result!['tools'] as List) (t as Map)['name'],
    ];
    expect(names, containsAll(['send_message', 'wait_for_message', 'finish_task', 'leave']));
  });

  test('send_message routes to the target member mailbox', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final target = AgentNode(memberId: 'worker', state: MemberState.busy);
    bus.declareMember(target);
    final handler = TeammateBusMcpHandler(bus: bus);

    final res = await handler.handle(
      'leader',
      const JsonRpcRequest(id: 2, method: 'tools/call', params: {
        'name': 'send_message',
        'arguments': {'to': 'worker', 'content': 'do X'},
      }),
    );

    expect(target.inbox.isEmpty, isFalse);
    expect((res!.result!['content'] as List).first, {'type': 'text', 'text': 'sent'});
  });

  test('finish_task retires caller and broadcasts; leave retires caller', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final lead = AgentNode(memberId: 'leader', state: MemberState.busy);
    final w = AgentNode(memberId: 'w', state: MemberState.busy);
    bus..declareMember(lead)..declareMember(w);
    final handler = TeammateBusMcpHandler(bus: bus);

    await handler.handle('leader', const JsonRpcRequest(id: 3, method: 'tools/call',
        params: {'name': 'finish_task', 'arguments': {'result': 'done'}}));
    expect(lead.state, MemberState.retired);
    expect(w.inbox.isEmpty, isFalse); // stand-down broadcast

    await handler.handle('w', const JsonRpcRequest(id: 4, method: 'tools/call',
        params: {'name': 'leave', 'arguments': {}}));
    expect(w.state, MemberState.retired);
  });
}
