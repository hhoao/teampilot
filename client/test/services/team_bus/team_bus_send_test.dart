import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('receive parks until a message is delivered to the member inbox', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final node = AgentNode(memberId: 'leader', state: MemberState.busy);
      bus.declareMember(node);

      List<TeamMessage>? got;
      bus.receive('leader', timeout: const Duration(seconds: 30)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isNull);

      node.inbox.deliver(TeamMessage(id: '1', from: 'w', to: 'leader', content: 'hi'));
      async.elapse(const Duration(milliseconds: 50));
      expect(got!.single.content, 'hi');
    });
  });

  test('receive on unknown member returns an empty batch', () {
    fakeAsync((async) {
      final bus = TeamBus(launcher: FakeMemberLauncher());
      List<TeamMessage>? got;
      bus.receive('ghost', timeout: const Duration(seconds: 1)).then((b) => got = b);
      async.flushMicrotasks();
      expect(got, isEmpty);
    });
  });
}
