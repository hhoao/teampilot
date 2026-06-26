import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';

void main() {
  group('defaultSessionSpecFor', () {
    test('returns local shell when cwd matches local folder', () {
      final folders = [
        const WorkspaceFolder(path: '/home/user/proj'),
      ];
      final spec = defaultSessionSpecFor(
        cwd: '/home/user/proj',
        folders: folders,
        fallbackLocalShell: '/bin/bash',
      );
      expect(spec, const WorkspaceTerminalLocalSpec('/bin/bash'));
    });

    test('returns workspace target when cwd matches ssh folder', () {
      final folders = [
        const WorkspaceFolder(
          path: '/remote/proj',
          targetId: 'ssh:profile-1',
        ),
      ];
      final spec = defaultSessionSpecFor(
        cwd: '/remote/proj',
        folders: folders,
        fallbackLocalShell: '/bin/bash',
      );
      expect(
        spec,
        const WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'),
      );
    });

    test('falls back to first folder target when cwd unmatched', () {
      final folders = [
        const WorkspaceFolder(
          path: '/remote/proj',
          targetId: 'ssh:profile-1',
        ),
      ];
      final spec = defaultSessionSpecFor(
        cwd: '/other/path',
        folders: folders,
        fallbackLocalShell: '/bin/zsh',
      );
      expect(
        spec,
        const WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'),
      );
    });
  });
}
