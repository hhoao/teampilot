import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/pages/chat/chat_workbench_slice.dart';

void main() {
  group('ChatWorkbenchSlice.isActiveSessionConnecting', () {
    test('false when connecting id does not match active session', () {
      const slice = ChatWorkbenchSlice(
        stateVersion: 1,
        activeSessionId: 'session-a',
        selectedMemberId: 'agent',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionConnectingId: 'session-b',
        sessionLaunchError: null,
      );

      expect(slice.isActiveSessionConnecting, isFalse);
    });

    test('false when active session cleared but connecting id remains', () {
      const slice = ChatWorkbenchSlice(
        stateVersion: 1,
        activeSessionId: null,
        selectedMemberId: '',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionConnectingId: 'session-a',
        sessionLaunchError: null,
      );

      expect(slice.isActiveSessionConnecting, isFalse);
    });

    test('true when pending materialization', () {
      const slice = ChatWorkbenchSlice(
        stateVersion: 1,
        activeSessionId: null,
        selectedMemberId: '',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionConnectingId: 'pending',
        sessionLaunchError: null,
      );

      expect(slice.isActiveSessionConnecting, isTrue);
    });
  });

  group('ChatState.isActiveSessionConnecting', () {
    test('false when active session cleared but connecting id remains', () {
      const state = ChatState(
        tabs: [
          ChatTabInfo(id: 'session-a', title: 'Chat', subtitle: '/tmp'),
        ],
        activeSessionId: null,
        sessionConnectingId: 'session-a',
      );

      expect(state.isActiveSessionConnecting, isFalse);
    });
  });
}
