import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/models/team_config.dart';

ChatTab _tab(String id) => ChatTab(
  info: ChatTabInfo(id: id, title: id, subtitle: ''),
  cliTeamName: id,
);

void main() {
  test('append + bySessionId + toInfos', () {
    final store = ChatTabStore();
    store.append(_tab('a'));
    store.append(_tab('b'));

    expect(store.length, 2);
    expect(store.bySessionId('b')!.cliTeamName, 'b');
    expect(store.toInfos().map((i) => i.id).toList(), ['a', 'b']);
  });

  test('activeTab clamps index', () {
    final store = ChatTabStore()
      ..append(_tab('a'))
      ..append(_tab('b'));
    expect(store.activeTab(99)!.info.id, 'b');
    expect(store.activeTab(-1)!.info.id, 'a');
  });

  test('defaultMemberId prefers team-lead', () {
    final store = ChatTabStore();
    const team = TeamProfile(
      id: 't',
      name: 'T',
      members: [
        TeamMemberConfig(id: 'member-1', name: 'dev'),
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      ],
    );
    expect(store.defaultMemberId(team), 'team-lead');
    expect(store.length, 0);
  });
}
