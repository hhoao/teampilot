import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

TerminalSession _testSession() => TerminalSession(
  executable: '/bin/bash',
  validateLaunch: false,
  parseExecutable: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceTerminalRegistry', () {
    test('groupFor lazily creates and reuses a group per workspace', () {
      final reg = WorkspaceTerminalRegistry();
      final a1 = reg.groupFor('A');
      final a2 = reg.groupFor('A');
      final b1 = reg.groupFor('B');
      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b1), isFalse);
      reg.disposeAll();
    });

    test('addEntry / entries stays scoped to its workspace group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      expect(a.entries.single, entry);
      expect(a.activeId, entry.id);
      expect(reg.groupFor('B').entries, isEmpty);
      reg.disposeAll();
    });

    test('disposeWorkspace disposes entries and drops the group', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final entry = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      reg.disposeWorkspace('A');
      expect(entry.session.isRunning, isFalse);
      expect(reg.groupFor('A').entries, isEmpty);
      reg.disposeAll();
    });

    test('removeEntry reselects the active id', () {
      final reg = WorkspaceTerminalRegistry();
      final a = reg.groupFor('A');
      final e1 = a.addEntry(
        cwd: '/tmp/a',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      final e2 = a.addEntry(
        cwd: '/tmp/a2',
        spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
        session: _testSession(),
        select: true,
      );
      expect(a.activeId, e2.id);
      a.removeEntry(e2.id);
      expect(a.activeId, e1.id);
      expect(a.entries.single, e1);
      reg.disposeAll();
    });
  });
}
