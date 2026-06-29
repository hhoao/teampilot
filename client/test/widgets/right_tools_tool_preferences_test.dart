import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';

void main() {
  group('RightToolsToolPreferences', () {
    test('needsLifecycleHost is false when all tabs hidden', () {
      const prefs = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: false,
        membersVisible: false,
        boardVisible: false,
      );
      expect(prefs.needsLifecycleHost, isFalse);
      expect(prefs.needsDiskSideEffects, isFalse);
    });

    test('needsDiskSideEffects only for file tree and git', () {
      const membersOnly = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: false,
        membersVisible: true,
        boardVisible: false,
      );
      expect(membersOnly.needsLifecycleHost, isTrue);
      expect(membersOnly.needsDiskSideEffects, isFalse);

      const fileTree = RightToolsToolPreferences(
        fileTreeVisible: true,
        gitVisible: false,
        membersVisible: false,
        boardVisible: false,
      );
      expect(fileTree.needsDiskSideEffects, isTrue);
    });
  });
}
