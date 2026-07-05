import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: const [
      WorkspaceFolder(path: '/main'),
      WorkspaceFolder(path: '/extra'),
    ],
    createdAt: 1,
  );

  group('WorkspaceLandingDirectoryResolver', () {
    test('resolveSelectedPath prefers stored path when valid', () {
      final resolver = WorkspaceLandingDirectoryResolver(
        workspace: workspace,
        storedPath: '/extra',
      );
      expect(resolver.resolveSelectedPath(), '/extra');
    });

    test('resolveSelectedPath uses current worktree when stored path is invalid',
        () {
      final resolver = WorkspaceLandingDirectoryResolver(
        workspace: workspace,
        storedPath: '/missing',
        worktreeState: WorktreeState(
          worktrees: [
            GitWorktree(
              path: '/repo',
              branch: 'refs/heads/main',
              head: 'abc',
              isBare: false,
              isMainWorktree: true,
            ),
            GitWorktree(
              path: '/repo/.worktrees/feature',
              branch: 'refs/heads/feature',
              head: 'def',
              isBare: false,
              isMainWorktree: false,
            ),
          ],
          currentWorktreePath: '/repo/.worktrees/feature',
        ),
      );
      expect(
        resolver.resolveSelectedPath(),
        '/repo/.worktrees/feature',
      );
    });

    test('resolveSelectedPath falls back to first folder option', () {
      final resolver = WorkspaceLandingDirectoryResolver(workspace: workspace);
      expect(resolver.resolveSelectedPath(), '/main');
    });

    test('resolveSelectedPath uses workspace primary when no options', () {
      final single = Workspace(
        workspaceId: 'ws-2',
        folders: const [WorkspaceFolder(path: '/only')],
        createdAt: 1,
      );
      final resolver = WorkspaceLandingDirectoryResolver(workspace: single);
      expect(resolver.resolveSelectedPath(), '/only');
    });

    test('mixed workspace options include runtime target subtitles', () {
      final mixed = Workspace(
        workspaceId: 'ws-mixed',
        folders: const [
          WorkspaceFolder(path: '/local', targetId: 'local'),
          WorkspaceFolder(path: '/remote', targetId: 'ssh:host-1'),
        ],
        createdAt: 1,
      );
      final resolver = WorkspaceLandingDirectoryResolver(
        workspace: mixed,
        runtimeTargets: [
          RuntimeTarget.ssh('host-1', label: 'Build Server'),
        ],
      );
      final subtitles = [
        for (final o in resolver.options) o.subtitle,
      ];
      expect(subtitles, ['This device', 'Build Server']);
    });
  });
}
