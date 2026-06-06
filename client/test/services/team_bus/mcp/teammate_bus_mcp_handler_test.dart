import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/persistence/in_memory_bus_message_log.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
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

  test('send_message resolves agentId and reports resolution', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher())
      ..installSessionContext(
        const TeamSessionContext(
          cliTeamName: 'testmixed-23',
          teamId: 'testmixed',
          teamName: 'TestMixed',
        ),
      );
    final developer = AgentNode(
      profile: TeammateRosterProfile.fromMember(
        member: const TeamMemberConfig(id: 'developer', name: 'Dev'),
        team: const TeamConfig(id: 'testmixed', name: 'TestMixed'),
        cliTeamName: 'testmixed-23',
        cwd: '/tmp',
      ),
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(developer);
    final handler = TeammateBusMcpHandler(bus: bus);

    final res = await handler.handle(
      'team-lead',
      const JsonRpcRequest(id: 10, method: 'tools/call', params: {
        'name': 'send_message',
        'arguments': {
          'to': 'developer@testmixed-23',
          'content': 'hello',
        },
      }),
    );

    expect(developer.inbox.isEmpty, isFalse);
    expect(res!.result!['isError'], isFalse);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('sent to developer'));
  });

  test('send_message returns tool error for unknown recipient', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode.test(
        memberId: 'team-lead',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ),
    );
    final handler = TeammateBusMcpHandler(bus: bus);

    final res = await handler.handle(
      'team-lead',
      const JsonRpcRequest(id: 11, method: 'tools/call', params: {
        'name': 'send_message',
        'arguments': {'to': 'ghost', 'content': 'hi'},
      }),
    );

    expect(res!.result!['isError'], isTrue);
    final text = (res.result!['content'] as List).first['text'] as String;
    expect(text, contains('unknown-member'));
    expect(text, contains('team-lead'));
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

  test('read_messages browses without consuming by default', () async {
    final bus = TeamBus(
      launcher: FakeMemberLauncher(),
      messageLog: InMemoryBusMessageLog(),
    );
    final leader = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(leader);
    // Single source: deliver once; the inbox owns memory + log.
    leader.inbox.deliver(
      const TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'),
    );
    final handler = TeammateBusMcpHandler(bus: bus);

    // No mark_read in the call → default browse, must NOT consume.
    await handler.handle(
      'leader',
      const JsonRpcRequest(id: 3, method: 'tools/call', params: {
        'name': 'read_messages',
        'arguments': <String, Object?>{},
      }),
    );
    expect(leader.inbox.unreadCount, 1, reason: 'browse must not drain hot queue');
    expect(await bus.unreadCountFor('leader'), 1);

    // Explicit mark_read=true consumes the page.
    await handler.handle(
      'leader',
      const JsonRpcRequest(id: 4, method: 'tools/call', params: {
        'name': 'read_messages',
        'arguments': {'mark_read': true},
      }),
    );
    expect(leader.inbox.unreadCount, 0);
    expect(await bus.unreadCountFor('leader'), 0);
  });

  test('read_messages exposes mark_read in its input schema', () async {
    final res = await _handler().handle(
      'leader',
      const JsonRpcRequest(id: 9, method: 'tools/list'),
    );
    final tools = res!.result!['tools'] as List;
    final readTool = tools.firstWhere((t) => (t as Map)['name'] == 'read_messages')
        as Map;
    final props =
        (readTool['inputSchema'] as Map)['properties'] as Map<String, Object?>;
    expect(props.containsKey('mark_read'), isTrue);
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
    final batch = await worker.inbox.waitAndTake(timeout: const Duration(seconds: 1));
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

  test('tools/list with a task queue adds queue tools and no claim_task',
      () async {
    final bus = TeamBus(launcher: FakeMemberLauncher(), taskQueue: TaskQueue());
    final res = await TeammateBusMcpHandler(bus: bus).handle(
      'developer',
      const JsonRpcRequest(id: 1, method: 'tools/list'),
    );
    final names = [
      for (final t in res!.result!['tools'] as List) (t as Map)['name'],
    ];
    expect(names, containsAll(['add_tasks', 'update_task', 'list_tasks']));
    expect(names, isNot(contains('claim_task')));
  });

  test('wait_for_message hands a worker a queued task (auto-claimed)', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher(), taskQueue: TaskQueue());
      bus.declareMember(AgentNode.test(
        memberId: 'developer',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.active,
      ));
      final handler = TeammateBusMcpHandler(bus: bus);

      JsonRpcResponse? res;
      handler.handle('developer', const JsonRpcRequest(id: 5, method: 'tools/call',
          params: {'name': 'wait_for_message', 'arguments': {}}))
        .then((r) => res = r);
      async.flushMicrotasks();
      expect(res, isNull); // parked: nothing to do

      bus.addTasks('lead', [const TeamTaskDraft(title: 'ship it', brief: 'do X')]);
      async.flushMicrotasks();

      final text = (res!.result!['content'] as List).first as Map;
      expect(text['text'], contains('ASSIGNED TASK'));
      expect(text['text'], contains('ship it'));
      expect(text['text'], contains('update_task'));
      // auto-claimed for the asking worker
      expect(bus.listTasks(status: TaskStatus.claimed).single.assignee,
          'developer');
    });
  });
}
