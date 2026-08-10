import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';
import 'package:teampilot/cubits/chat/tab_member_reclaim_watch.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_reclaim_policy.dart';

import '../../support/fake_terminal_session.dart';
import '../../services/team_bus/support/fake_member_launcher.dart';

const _lead = TeamMemberConfig(id: 'team-lead', name: 'lead');
const _worker = TeamMemberConfig(id: 'worker-1', name: 'worker');
const _team = TeamProfile(
  id: 't',
  name: 'T',
  teamMode: TeamMode.mixed,
  members: [_lead, _worker],
);

ChatTab _tabWithBus() {
  final tab = ChatTab(
    info: ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
    cliTeamName: 'ct',
  );
  tab.workbenchView = SessionWorkbenchView.chat; // nothing displayed
  return tab;
}

TeamBus _busWith(String memberId, MemberLifecycle lifecycle, MemberActivity activity) {
  final bus = TeamBus(launcher: FakeMemberLauncher());
  bus.declareMember(
    AgentNode.test(
      memberId: memberId,
      lifecycle: lifecycle,
      activity: activity,
    ),
  );
  return bus;
}

TabMemberReclaimWatch _watch(
  ChatTabStore store, {
  required void Function(String, String) onDiscard,
  required DateTime Function() now,
}) => TabMemberReclaimWatch(
  tabStore: store,
  reclaimEnabled: () => true,
  activeTeam: () => _team,
  policy: () => const TerminalReclaimPolicy(idleAfter: Duration(seconds: 2)),
  onDiscardMember: onDiscard,
  now: now,
);

void main() {
  test('reclaims an idle worker after threshold, never the lead', () {
    final store = ChatTabStore();
    final tab = _tabWithBus();
    store.registerSession(tab);
    final bus = _busWith('team-lead', MemberLifecycle.running, MemberActivity.turnDoneReady);
    bus.declareMember(
      AgentNode.test(
        memberId: 'worker-1',
        lifecycle: MemberLifecycle.running,
        activity: MemberActivity.turnDoneBusWait, // parked, idle
      ),
    );
    tab.teamBus = bus;
    tab.memberShells['team-lead'] = _runningShell();
    tab.memberShells['worker-1'] = _runningShell();

    final discarded = <(String, String)>[];
    var now = DateTime(2026, 8, 9, 12, 0, 0);
    final watch = _watch(store, onDiscard: (s, m) => discarded.add((s, m)), now: () => now);

    watch.tick(); // seeds idleSince
    expect(discarded, isEmpty);
    now = now.add(const Duration(seconds: 3));
    watch.tick();

    expect(discarded, contains(('sess', 'worker-1')));
    expect(discarded, isNot(contains(('sess', 'team-lead'))));
  });

  test('in-turn and unread members are never reclaimed', () async {
    final store = ChatTabStore();
    final tab = _tabWithBus();
    store.registerSession(tab);
    final bus = _busWith('worker-1', MemberLifecycle.running, MemberActivity.active);
    tab.teamBus = bus;
    tab.memberShells['worker-1'] = _runningShell();
    // Seed an unread so hasUnread also guards.
    bus.deliverUserCommand('worker-1', 'hello');

    final discarded = <(String, String)>[];
    final watch = _watch(
      store,
      onDiscard: (s, m) => discarded.add((s, m)),
      now: () => DateTime(2026, 8, 9, 12, 0, 0),
    );

    watch.tick();
    expect(discarded, isEmpty, reason: 'in-turn member is protected');
  });
}

FakeTerminalSession _runningShell() {
  final shell = FakeTerminalSession(executable: 'claude');
  shell.connect(workingDirectory: '/work');
  return shell;
}
