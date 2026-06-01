import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('order A: message arrives while busy, idle edge then rings doorbell', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));
    expect(launcher.woken, isEmpty); // busy: only enqueued

    bus.onMemberIdle('leader'); // idle edge with pending mail
    expect(launcher.woken.single.memberId, 'leader');
    expect(node.state, MemberState.busy);
  });

  test('order B: idle first (empty), message later → enqueue + doorbell', () async {
    final launcher = FakeMemberLauncher();
    final bus = TeamBus(launcher: launcher);
    final node = AgentNode(memberId: 'leader', state: MemberState.busy);
    bus.declareMember(node);

    bus.onMemberIdle('leader'); // empty → idle, no wake
    expect(node.state, MemberState.idle);
    expect(launcher.woken, isEmpty);

    await bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'x'));
    expect(launcher.woken.single.memberId, 'leader');
    expect(node.state, MemberState.busy);
  });

  test('order C: in-loop member receives via tool_result (waiter), no doorbell', () {
    fakeAsync((async) {
      final launcher = FakeMemberLauncher();
      final bus = TeamBus(launcher: launcher);
      final node = AgentNode(memberId: 'leader', state: MemberState.busy);
      bus.declareMember(node);

      List<TeamMessage>? got;
      bus.receive('leader', timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull); // parked in wait_for_message

      bus.send(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'reply'));
      async.elapse(const Duration(milliseconds: 50)); // debounce
      expect(got!.single.content, 'reply');
      expect(launcher.woken, isEmpty); // clean tool_result path
    });
  });
}
