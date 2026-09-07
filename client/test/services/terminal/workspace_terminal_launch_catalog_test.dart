import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
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

    test('single local folder keeps one plain entry per shell', () {
      final items = WorkspaceTerminalLaunchCatalog.buildLocalShells([
        const WorkspaceFolder(path: '/work/main'),
      ]);
      final shellItems = items
          .where((i) => i.spec is WorkspaceTerminalLocalSpec)
          .toList(growable: false);
      // No folder suffixes: every label is the plain shell label, unpinned.
      expect(shellItems.every((i) => i.launchCwd == null), isTrue);
      expect(shellItems.any((i) => i.label.contains('·')), isFalse);
    });

    test('multiple local folders expand one entry per folder', () {
      final items = WorkspaceTerminalLaunchCatalog.buildLocalShells([
        const WorkspaceFolder(path: '/work/main'),
        const WorkspaceFolder(path: '/work/other'),
      ]);
      final shellItems = items
          .where((i) => i.spec is WorkspaceTerminalLocalSpec)
          .toList(growable: false);
      // First folder stays the plain default (caller cwd); extras pin theirs.
      final plain = shellItems.where((i) => !i.label.contains('·')).toList();
      final pinned = shellItems
          .where((i) => i.label.contains('·'))
          .toList(growable: false);
      expect(plain, isNotEmpty);
      expect(plain.every((i) => i.launchCwd == null), isTrue);
      expect(pinned, isNotEmpty);
      expect(pinned.every((i) => i.launchCwd == '/work/other'), isTrue);
      expect(pinned.every((i) => i.label.endsWith('· other')), isTrue);
    });

    test('duplicate folder basenames fall back to the full path label', () {
      final items = WorkspaceTerminalLaunchCatalog.buildLocalShells([
        const WorkspaceFolder(path: '/a/project'),
        const WorkspaceFolder(path: '/b/project'),
      ]);
      final pinned = items
          .where((i) => i.spec is WorkspaceTerminalLocalSpec)
          .where((i) => i.launchCwd != null)
          .toList(growable: false);
      expect(pinned, isNotEmpty);
      expect(pinned.every((i) => i.label.endsWith('· /b/project')), isTrue);
    });

    test('non-local folders are not expanded', () {
      final items = WorkspaceTerminalLaunchCatalog.buildLocalShells([
        const WorkspaceFolder(path: '/work/main'),
        const WorkspaceFolder(path: '/remote/proj', targetId: 'ssh:prod'),
      ]);
      final shellItems = items
          .where((i) => i.spec is WorkspaceTerminalLocalSpec)
          .toList(growable: false);
      expect(shellItems.every((i) => i.launchCwd == null), isTrue);
      expect(shellItems.any((i) => i.label.contains('·')), isFalse);
    });
  });
}
