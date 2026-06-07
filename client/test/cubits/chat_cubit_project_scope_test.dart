import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatCubit _cubit() => ChatCubit(executableResolver: () => '/bin/true');

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  group('ChatCubit project scoping', () {
    test('setActiveProject swaps the visible tab list', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      // Mirror into state the way the launch flow does:
      cubit.refreshActiveProjectTabs();
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);

      cubit.setActiveProject('B');
      expect(cubit.state.tabs, isEmpty);

      cubit.setActiveProject('A');
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);
      addTearDown(cubit.close);
    });

    test('switching projects preserves each project active index', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.append(_tab('a3'));
      cubit.refreshActiveProjectTabs();
      cubit.selectTab(2);
      expect(cubit.state.activeTabIndex, 2);

      cubit.setActiveProject('B');
      cubit.setActiveProject('A');
      expect(cubit.state.activeTabIndex, 2);
      addTearDown(cubit.close);
    });

    test('openTabCountForProject counts only session tabs in that bucket', () {
      final cubit = _cubit();
      cubit.setActiveProject('A');
      cubit.tabStore.append(_tab('sess-1'));
      cubit.tabStore.append(_tab('local-team'));
      cubit.setActiveProject('B');
      cubit.tabStore.append(_tab('sess-2'));
      expect(cubit.openTabCountForProject('A'), 1);
      expect(cubit.openTabCountForProject('B'), 1);
      addTearDown(cubit.close);
    });
  });
}
