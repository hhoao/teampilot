import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_terminal_session_spec.dart';

void main() {
  group('defaultSessionSpecFor', () {
    test('returns local shell when cwd matches local folder', () {
      final folders = [const WorkspaceFolder(path: '/home/user/proj')];
      final spec = defaultSessionSpecFor(
        cwd: '/home/user/proj',
        folders: folders,
        fallbackLocalShell: '/bin/bash',
        home: RuntimeTarget.local(),
      );
      expect(spec, const WorkspaceTerminalLocalSpec('/bin/bash'));
    });

    test('returns workspace target when cwd matches ssh folder', () {
      final folders = [
        const WorkspaceFolder(path: '/remote/proj', targetId: 'ssh:profile-1'),
      ];
      final spec = defaultSessionSpecFor(
        cwd: '/remote/proj',
        folders: folders,
        fallbackLocalShell: '/bin/bash',
        home: RuntimeTarget.local(),
      );
      expect(spec, const WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'));
    });

    test('falls back to first folder target when cwd unmatched', () {
      final folders = [
        const WorkspaceFolder(path: '/remote/proj', targetId: 'ssh:profile-1'),
      ];
      final spec = defaultSessionSpecFor(
        cwd: '/other/path',
        folders: folders,
        fallbackLocalShell: '/bin/zsh',
        home: RuntimeTarget.local(),
      );
      expect(spec, const WorkspaceTerminalWorkspaceTargetSpec('ssh:profile-1'));
    });

    test('defaultSessionSpecFor uses home ssh when folder target is local', () {
      final home = RuntimeTarget.ssh('p1', label: 'box');
      final spec = defaultSessionSpecFor(
        cwd: '/repo',
        folders: const [WorkspaceFolder(path: '/repo')],
        fallbackLocalShell: '/bin/bash',
        home: home,
      );
      expect(spec, isA<WorkspaceTerminalWorkspaceTargetSpec>());
      expect((spec as WorkspaceTerminalWorkspaceTargetSpec).targetId, 'ssh:p1');
    });

    test('defaultSessionSpecFor keeps LocalSpec when home is local', () {
      final spec = defaultSessionSpecFor(
        cwd: '/repo',
        folders: const [WorkspaceFolder(path: '/repo')],
        fallbackLocalShell: '/bin/bash',
        home: RuntimeTarget.local(),
      );
      expect(spec, isA<WorkspaceTerminalLocalSpec>());
    });
  });

  group('workspaceShellLaunchWorkingDirectory', () {
    const localCwd = '/home/hhoa/git/quanzhi/audit-apiv2';
    const localFolders = [WorkspaceFolder(path: localCwd)];

    test('does not cd SSH shells into a local-only workspace path', () {
      expect(
        workspaceShellLaunchWorkingDirectory(
          spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
          folders: localFolders,
          localCwd: localCwd,
          home: RuntimeTarget.local(),
        ),
        isEmpty,
      );
    });

    test('uses matching remote folder for an SSH profile', () {
      expect(
        workspaceShellLaunchWorkingDirectory(
          spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
          folders: const [
            WorkspaceFolder(path: localCwd),
            WorkspaceFolder(path: '/remote/proj', targetId: 'ssh:profile-1'),
          ],
          localCwd: localCwd,
          home: RuntimeTarget.local(),
        ),
        '/remote/proj',
      );
    });

    test('falls back to SSH default when no remote folder exists', () {
      expect(
        workspaceShellLaunchWorkingDirectory(
          spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
          folders: localFolders,
          localCwd: localCwd,
          home: RuntimeTarget.local(),
          sshDefaultWorkingDirectory: '/home/remote',
        ),
        '/home/remote',
      );
    });

    test('keeps local cwd when home runtime is the same SSH target', () {
      expect(
        workspaceShellLaunchWorkingDirectory(
          spec: const WorkspaceTerminalSshProfileSpec('p1'),
          folders: localFolders,
          localCwd: localCwd,
          home: RuntimeTarget.ssh('p1', label: 'box'),
        ),
        localCwd,
      );
    });

    test('keeps local cwd for a local shell spec', () {
      expect(
        workspaceShellLaunchWorkingDirectory(
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          folders: localFolders,
          localCwd: localCwd,
          home: RuntimeTarget.local(),
        ),
        localCwd,
      );
    });
  });

  group('workspaceShellShouldApplySyncedCwd', () {
    test('rejects syncing a local workspace path onto an SSH shell', () {
      expect(
        workspaceShellShouldApplySyncedCwd(
          spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
          syncedCwd: '/home/hhoa/git/quanzhi/audit-apiv2',
          folders: const [
            WorkspaceFolder(path: '/home/hhoa/git/quanzhi/audit-apiv2'),
          ],
          home: RuntimeTarget.local(),
        ),
        isFalse,
      );
    });

    test('allows syncing a local path onto a local shell', () {
      expect(
        workspaceShellShouldApplySyncedCwd(
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          syncedCwd: '/home/hhoa/git/quanzhi/audit-apiv2',
          folders: const [
            WorkspaceFolder(path: '/home/hhoa/git/quanzhi/audit-apiv2'),
          ],
          home: RuntimeTarget.local(),
        ),
        isTrue,
      );
    });
  });

  group('workspaceShellCanConnect', () {
    test('allows empty cwd for SSH shells', () {
      expect(
        workspaceShellCanConnect(
          spec: const WorkspaceTerminalSshProfileSpec('profile-1'),
          cwd: '',
          home: RuntimeTarget.local(),
        ),
        isTrue,
      );
    });

    test('rejects empty cwd for local shells', () {
      expect(
        workspaceShellCanConnect(
          spec: const WorkspaceTerminalLocalSpec('/bin/bash'),
          cwd: '',
          home: RuntimeTarget.local(),
        ),
        isFalse,
      );
    });
  });
}
