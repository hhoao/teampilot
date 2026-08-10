import 'package:flutter_test/flutter_test.dart';
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
}
