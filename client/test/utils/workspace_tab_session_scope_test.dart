import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/pages/chat/chat_scoped_tab_view.dart';
import 'package:teampilot/utils/workspace_tab_session_scope.dart';

ChatCubit _cubit() => ChatCubit(executableResolver: () => '/bin/true');

ChatTab _tab(String id, {String? launchError}) => ChatTab(
      info: ChatTabInfo(
        id: id,
        title: id,
        subtitle: '',
        launchError: launchError,
      ),
      cliTeamName: id,
    );

void main() {
  group('scopedActiveSessionId', () {
    test('foreground tab follows ChatState.activeSessionId', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.refreshActiveWorkspaceTabs();

      expect(scopedActiveSessionId(cubit, 'tab-A'), 'a1');
    });

    test('background tab freezes to saved bucket index', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.setActiveWorkspace('tab-B', currentActiveIndex: 1);

      cubit.tabStore.append(_tab('b1'));
      cubit.refreshActiveWorkspaceTabs();

      expect(scopedActiveSessionId(cubit, 'tab-A'), 'a2');
      expect(scopedActiveSessionId(cubit, 'tab-B'), 'b1');
    });
  });

  group('scopedActiveChatTab', () {
    test('foreground tab follows ChatState active index', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.refreshActiveWorkspaceTabs();

      expect(scopedActiveChatTab(cubit, 'tab-A')?.info.id, 'a1');
    });

    test('background tab freezes to saved bucket index', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.tabStore.append(_tab('a2'));
      cubit.tabStore.setActiveWorkspace('tab-B', currentActiveIndex: 1);
      cubit.tabStore.append(_tab('b1'));
      cubit.refreshActiveWorkspaceTabs();

      expect(scopedActiveChatTab(cubit, 'tab-A')?.info.id, 'a2');
      expect(scopedActiveChatTab(cubit, 'tab-B')?.info.id, 'b1');
    });
  });

  group('ChatScopedTabView', () {
    test('reads frozen bucket for background workspace tab', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.refreshActiveWorkspaceTabs();

      cubit.setActiveWorkspace('tab-B');
      cubit.tabStore.append(_tab('b1'));
      cubit.refreshActiveWorkspaceTabs();

      final background = ChatScopedTabView.resolve(cubit, 'tab-A');
      expect(background.tabs.map((t) => t.id), ['a1']);
      expect(background.activeTabIndex, 0);

      final foreground = ChatScopedTabView.resolve(cubit, 'tab-B');
      expect(foreground.tabs.map((t) => t.id), ['b1']);
      expect(foreground.activeTabIndex, 0);
    });

    test('background bucket does not inherit foreground sessionLaunchError', () {
      final cubit = _cubit();
      addTearDown(cubit.close);

      cubit.setActiveWorkspace('tab-A');
      cubit.tabStore.append(_tab('a1'));
      cubit.refreshActiveWorkspaceTabs();

      cubit.setActiveWorkspace('tab-B');
      cubit.tabStore.append(_tab('b1'));
      cubit.refreshActiveWorkspaceTabs();

      cubit.emit(
        cubit.state.copyWith(sessionLaunchError: 'foreground-only error'),
      );

      final background = ChatScopedTabView.resolve(cubit, 'tab-A');
      expect(background.workbenchSlice.sessionLaunchError, isNull);

      final foreground = ChatScopedTabView.resolve(cubit, 'tab-B');
      expect(
        foreground.workbenchSlice.sessionLaunchError,
        'foreground-only error',
      );
    });
  });
}
