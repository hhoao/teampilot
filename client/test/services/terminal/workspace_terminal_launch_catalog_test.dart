import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/workspace_terminal_launch_catalog.dart';

void main() {
  group('WorkspaceTerminalLaunchCatalog.buildLocalShells', () {
    test('returns at least one local shell session item', () {
      final items = WorkspaceTerminalLaunchCatalog.buildLocalShells();
      expect(items, isNotEmpty);
      expect(items.every((i) => !i.isDivider), isTrue);
      expect(items.every((i) => i.spec != null), isTrue);
      expect(items.every((i) => i.label.isNotEmpty), isTrue);
    });
  });
}
