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

  test('tools/list returns teammate-bus tools', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 1, method: 'tools/list'),
    );
    final names = [
      for (final t in res!.result!['tools'] as List) (t as Map)['name'],
    ];
    expect(names, [
      'list_teammates',
      'send_message',
      'read_messages',
      'wait_for_message',
    ]);
  });

  test('list_teammates returns roster with state and unread counts', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final leader = AgentNode.test(
      memberId: 'team-lead',
      displayName: 'Team Lead',
      cli: 'claude',
      isTeamLead: true,
      lifecycle: MemberLifecycle.running, activity: MemberActivity.active,
    );
    final worker = AgentNode.test(
      memberId: 'developer',
      displayName: 'Developer',
      cli: 'opencode',
      lifecycle: MemberLifecycle.declared,
    );
    bus
      ..declareMember(leader)
      ..declareMember(worker);
    worker.inbox.deliver(
      TeamMessage(id: '1', from: 'team-lead', to: 'developer', content: 'hi'),
    );
    final handler = TeammateBusMcpHandler(bus: bus);

    final res = await handler.handle(
      'team-lead',
      const JsonRpcRequest(id: 8, method: 'tools/call', params: {
        'name': 'list_teammates',
        'arguments': {},
      }),
    );

    final text = (res!.result!['content'] as List).first['text'] as String;
    expect(text, contains('--- team-lead (self) ---'));
    expect(text, contains('display_name: Team Lead'));
    expect(text, contains('cli: claude'));
    expect(text, contains('--- developer ---'));
    expect(text, contains('bus.lifecycle: declared'));
    expect(text, contains('bus.activity: none'));
    expect(text, contains('bus.unread: 1'));
  });

  test('send_message routes to the target member mailbox', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final target = AgentNode.test(memberId: 'worker', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
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
    final leader = AgentNode.test(memberId: 'team-lead', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
    final worker = AgentNode.test(memberId: 'developer', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
    final declared = AgentNode.test(memberId: 'reviewer', lifecycle: MemberLifecycle.declared);
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
    expect(declared.lifecycle, MemberLifecycle.running);
    expect(launcher.materialized.single.memberId, 'reviewer');
    expect(declared.inbox.isEmpty, isFalse);
    final batch = await worker.inbox.waitBatch(timeout: const Duration(seconds: 1));
    expect(batch.single.content, 'all hands');
    expect(batch.single.from, 'team-lead');
  });

  test('wait_for_message blocks indefinitely without timeout_ms', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      bus.declareMember(AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active));
      final handler = TeammateBusMcpHandler(bus: bus);
      JsonRpcResponse? res;
      handler.handle('leader', const JsonRpcRequest(id: 6, method: 'tools/call',
          params: {'name': 'wait_for_message', 'arguments': {}}))
        .then((r) => res = r);
      async.elapse(const Duration(hours: 1));
      expect(res, isNull); // still blocked
    });
  });

  test('wait_for_message returns a batch when a message is delivered', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final leader = AgentNode.test(memberId: 'leader', lifecycle: MemberLifecycle.running, activity: MemberActivity.active);
      bus.declareMember(leader);
      final handler = TeammateBusMcpHandler(bus: bus);

      JsonRpcResponse? res;
      handler.handle('leader', const JsonRpcRequest(id: 5, method: 'tools/call',
          params: {'name': 'wait_for_message', 'arguments': {}}))
        .then((r) => res = r);
      async.flushMicrotasks();
      expect(res, isNull); // blocked (no timeout)

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
}
