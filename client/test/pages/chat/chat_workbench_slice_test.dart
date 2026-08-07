import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_slice.dart';

void main() {
  group('ChatWorkbenchSlice', () {
    test('equality reflects stateVersion and active session', () {
      const a = ChatWorkbenchSlice(
        stateVersion: 1,
        activeSessionId: 's1',
        selectedMemberId: 'agent',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionLaunchError: null,
      );
      const same = ChatWorkbenchSlice(
        stateVersion: 1,
        activeSessionId: 's1',
        selectedMemberId: 'agent',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionLaunchError: null,
      );
      const changed = ChatWorkbenchSlice(
        stateVersion: 2,
        activeSessionId: 's1',
        selectedMemberId: 'agent',
        activeTabIndex: 0,
        tabCount: 1,
        newChatActive: false,
        sessionLaunchError: null,
      );

      expect(a, same);
      expect(a == changed, isFalse);
    });
  });
}
