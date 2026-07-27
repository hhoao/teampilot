import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/workbench/workbench_center_mode.dart';

void main() {
  group('resolveWorkbenchCenterMode', () {
    test('compose wins even when activeTabId is set', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: true, activeTabId: 'x'),
        WorkbenchCenterMode.compose,
      );
    });

    test('welcome when not compose and active is null', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: false, activeTabId: null),
        WorkbenchCenterMode.welcome,
      );
    });

    test('tab when not compose and active is set', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: false, activeTabId: 's1'),
        WorkbenchCenterMode.tab,
      );
    });
  });

  group('kWorkbenchWelcomeCommandIds', () {
    test('exact curated order', () {
      expect(kWorkbenchWelcomeCommandIds, [
        CommandIds.sessionNewTab,
        CommandIds.togglePanel,
        CommandIds.toggleSidebar,
        CommandIds.workspaceSearch,
        CommandIds.showCheatsheet,
      ]);
    });
  });
}
