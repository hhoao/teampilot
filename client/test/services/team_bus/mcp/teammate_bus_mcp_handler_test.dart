import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

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

  test('send_message with to=* broadcasts and materializes declared teammates', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final leader = AgentNode(memberId: 'team-lead', state: MemberState.busy);
    final worker = AgentNode(memberId: 'developer', state: MemberState.busy);
    final declared = AgentNode(memberId: 'reviewer', state: MemberState.declared);
    bus
      ..declareMember(leader)
      ..declareMember(worker)
      ..declareMember(declared);
    final handler = TeammateBusMcpHandler(bus: bus);

    await handler.handle(
      'team-lead',
      const JsonRpcRequest(id: 7, method: 'tools/call', params: {
        'name': 'send_message',
        'arguments': {'to': '*', 'content': 'all hands'},
      }),
    );

    expect(leader.inbox.isEmpty, isTrue); // sender skipped
    expect(worker.inbox.isEmpty, isFalse);
    expect(declared.state, MemberState.busy);
    expect(launcher.materialized.single.memberId, 'reviewer');
    expect(declared.inbox.isEmpty, isFalse);
    final batch = await worker.inbox.waitBatch(timeout: const Duration(seconds: 1));
    expect(batch.single.content, 'all hands');
    expect(batch.single.from, 'team-lead');
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

  test('wait_for_message returns a batch when a message is delivered', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final leader = AgentNode(memberId: 'leader', state: MemberState.busy);
      bus.declareMember(leader);
      final handler = TeammateBusMcpHandler(bus: bus);

      JsonRpcResponse? res;
      handler.handle('leader', const JsonRpcRequest(id: 5, method: 'tools/call',
          params: {'name': 'wait_for_message', 'arguments': {'timeout_ms': 300000}}))
        .then((r) => res = r);
      async.flushMicrotasks();
      expect(res, isNull); // blocked

      leader.inbox.deliver(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'reply'));
      async.elapse(const Duration(milliseconds: 50));
      final text = (res!.result!['content'] as List).first as Map;
      expect(text['text'], contains('FROM w'));
      expect(text['text'], contains('reply'));
    });
  });

  test('config entry points at endpoint with X-Member header', () {
    final entry = teammateBusMcpServerConfig(
      endpoint: Uri.parse('http://127.0.0.1:54321/mcp'),
      memberId: 'worker-1',
    );
    expect(entry['type'], 'http');
    expect(entry['url'], 'http://127.0.0.1:54321/mcp');
    expect((entry['headers'] as Map)['X-Member'], 'worker-1');
  });

  test('wait_for_message returns EMPTY sentinel on timeout', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(AgentNode(memberId: 'leader', state: MemberState.busy));
      final handler = TeammateBusMcpHandler(bus: bus);
      JsonRpcResponse? res;
      handler.handle('leader', const JsonRpcRequest(id: 6, method: 'tools/call',
          params: {'name': 'wait_for_message', 'arguments': {'timeout_ms': 1000}}))
        .then((r) => res = r);
      async.elapse(const Duration(milliseconds: 1000));
      expect(((res!.result!['content'] as List).first as Map)['text'], contains('EMPTY'));
    });
  });
}
