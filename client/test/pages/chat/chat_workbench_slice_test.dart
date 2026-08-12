import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/pages/chat/chat_workbench_slice.dart';

void main() {
  group('ChatWorkbenchSlice', () {
    test('equality reflects active session and structural fields', () {
      const a = ChatWorkbenchSlice(
        activeSessionId: 's1',
        selectedMemberId: 'agent',
        sessionLaunchError: null,
      );
      const same = ChatWorkbenchSlice(
        activeSessionId: 's1',
        selectedMemberId: 'agent',
        sessionLaunchError: null,
      );
      const changed = ChatWorkbenchSlice(
        activeSessionId: 's2',
        selectedMemberId: 'agent',
        sessionLaunchError: null,
      );

      expect(a, same);
      expect(a == changed, isFalse);
    });
  });

  group('ChatWorkbenchSlice.fromScope', () {
    test('projects the scoped identity', () {
      const state = ChatState(sessionLaunchError: 'boom');
      final slice = ChatWorkbenchSlice.fromScope(
        state: state,
        activeSessionId: 'sess-1',
        selectedMemberId: 'team-lead',
      );
      expect(slice.activeSessionId, 'sess-1');
      expect(slice.selectedMemberId, 'team-lead');
      expect(slice.sessionLaunchError, 'boom');
    });
  });
}
