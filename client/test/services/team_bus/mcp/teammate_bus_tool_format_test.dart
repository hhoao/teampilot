import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/mcp/toolkit/teammate_bus_tool_format.dart';
import 'package:teampilot/services/team_bus/persistence/bus_message_page.dart';
import 'package:teampilot/services/team_bus/tasks/task_queue.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/teammate_roster_profile.dart';

import '../support/fake_member_launcher.dart';

void main() {
  test('encodeRoster empty → members []', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final raw = TeammateBusToolFormat.encodeRoster(bus, 'lead');
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['caller'], 'lead');
    expect(json['members'], isEmpty);
    expect(raw.trimLeft(), startsWith('{'));
  });

  test('encodeRoster member includes machine keys when profile set', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(
      AgentNode(
        profile: const TeammateRosterProfile(
          memberId: 'dev',
          displayName: 'Dev',
          cwd: '/work',
          machine: 'root@h:22',
          machineKind: 'ssh',
          machineId: 'ssh:p1',
        ),
      ),
    );
    final json =
        jsonDecode(TeammateBusToolFormat.encodeRoster(bus, 'dev'))
            as Map<String, Object?>;
    final member = (json['members'] as List).single as Map<String, Object?>;
    expect(member['machine'], 'root@h:22');
    expect(member['machine_kind'], 'ssh');
    expect(member['machine_id'], 'ssh:p1');
    expect(member['cwd'], '/work');
    expect(member['self'], isTrue);
  });

  test('encodeTasks empty → {tasks:[]}', () {
    final bus = TeamBus(launcher: FakeMemberLauncher(), taskQueue: TaskQueue());
    bus.declareMember(AgentNode.test(memberId: 'w'));
    expect(
      jsonDecode(TeammateBusToolFormat.encodeTasks(bus, const [], 'w')),
      {'tasks': <Object>[]},
    );
  });

  test('encodeTaskAssignment is bare task object without ASSIGNED prose', () {
    const task = TeamTask(
      id: 't1',
      seq: 1,
      title: 'ship',
      brief: 'do X',
      createdBy: 'lead',
      createdAt: 1,
      status: TaskStatus.claimed,
      assignee: 'w',
    );
    final raw = TeammateBusToolFormat.encodeTaskAssignment(task);
    expect(raw, isNot(contains('ASSIGNED TASK')));
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['id'], 't1');
    expect(json['title'], 'ship');
    expect(json['brief'], 'do X');
  });

  test('encodeBatch empty → {messages:[]}', () {
    expect(
      jsonDecode(TeammateBusToolFormat.encodeBatch(const [])),
      {'messages': <Object>[]},
    );
  });

  test('encodeMessagePage empty keeps unread fields', () {
    const page = BusMessagePage(
      messages: [],
      hasMore: false,
      totalUnread: 2,
    );
    final json =
        jsonDecode(TeammateBusToolFormat.encodeMessagePage(page))
            as Map<String, Object?>;
    expect(json['messages'], isEmpty);
    expect(json['total_unread'], 2);
    expect(json['has_more'], isFalse);
  });

  test('encodeRoster omits machine trio when machineId empty', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'dev'));
    final json =
        jsonDecode(TeammateBusToolFormat.encodeRoster(bus, 'dev'))
            as Map<String, Object?>;
    final member = (json['members'] as List).single as Map<String, Object?>;
    expect(member.containsKey('machine'), isFalse);
    expect(member.containsKey('machine_kind'), isFalse);
    expect(member.containsKey('machine_id'), isFalse);
  });

  test('unknownRecipientHint is JSON object', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(memberId: 'a', displayName: 'A'));
    final raw = TeammateBusToolFormat.unknownRecipientHint(bus);
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['known_recipients'], isA<List>());
  });
}
