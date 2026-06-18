import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';

ChatCubit _cubit() => ChatCubit(executableResolver: () => '/bin/true');

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  group('ChatCubit workspace scoping', () {
    test('setActiveWorkspace swaps the visible tab list', () {
      final cubit = _cubit();
      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      // Mirror into state the way the launch flow does:
      cubit.refreshActiveWorkspaceTabs();
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);

      cubit.setActiveWorkspace('B');
      expect(cubit.state.tabs, isEmpty);

      cubit.setActiveWorkspace('A');
      expect(cubit.state.tabs.map((t) => t.id), ['a1', 'a2']);
      addTearDown(cubit.close);
    });

    test('switching workspaces preserves each workspace active index', () {
      final cubit = _cubit();
      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.append(_tab('a3'));
      cubit.refreshActiveWorkspaceTabs();
      cubit.selectTab(2);
      expect(cubit.state.activeTabIndex, 2);

      cubit.setActiveWorkspace('B');
      cubit.setActiveWorkspace('A');
      expect(cubit.state.activeTabIndex, 2);
      addTearDown(cubit.close);
    });

    test('openTabCountForWorkspace counts only session tabs in that bucket', () {
      final cubit = _cubit();
      cubit.setActiveWorkspace('A');
      cubit.tabStore.append(_tab('sess-1'));
      cubit.tabStore.append(_tab('local-team'));
      cubit.setActiveWorkspace('B');
      cubit.tabStore.append(_tab('sess-2'));
      expect(cubit.openTabCountForWorkspace('A'), 1);
      expect(cubit.openTabCountForWorkspace('B'), 1);
      addTearDown(cubit.close);
    });
  });
}
