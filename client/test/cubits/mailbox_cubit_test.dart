import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mailbox_cubit.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../services/team_bus/support/fake_member_launcher.dart';

void main() {
  test('attachUi polls the scoped bus and emits entries + unread count',
      () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.deliverUserCommand('leader', 'hello');

    final cubit = MailboxCubit(busForScope: (_) => bus);
    addTearDown(cubit.close);

    cubit.attachUi('tab-a');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(cubit.state.entries.single.content, 'hello');
    expect(cubit.state.totalUnread, 1);

    cubit.detachUi();
    expect(cubit.state.entries, isEmpty);
  });

  test('emits empty when scoped bus is null', () async {
    final cubit = MailboxCubit(busForScope: (_) => null);
    addTearDown(cubit.close);
    cubit.attachUi('tab-a');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cubit.state.entries, isEmpty);
    expect(cubit.state.totalUnread, 0);
  });
}
