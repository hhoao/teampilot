import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_body_kind.dart';

void main() {
  group('resolveWorkspaceTerminalBodyKind', () {
    test('empty cwd is noWorkingDirectory even with an entry flag', () {
      expect(
        resolveWorkspaceTerminalBodyKind(
          workingDirectory: '  ',
          hasActiveEntry: true,
        ),
        WorkspaceTerminalBodyKind.noWorkingDirectory,
      );
    });

    test('cwd ready without entry is emptyLauncher (no auto PTY)', () {
      expect(
        resolveWorkspaceTerminalBodyKind(
          workingDirectory: '/home/hhoa/Documents/TeamPilot',
          hasActiveEntry: false,
        ),
        WorkspaceTerminalBodyKind.emptyLauncher,
      );
    });

    test('cwd ready with active entry is activeSession', () {
      expect(
        resolveWorkspaceTerminalBodyKind(
          workingDirectory: '/repo',
          hasActiveEntry: true,
        ),
        WorkspaceTerminalBodyKind.activeSession,
      );
    });
  });
}
