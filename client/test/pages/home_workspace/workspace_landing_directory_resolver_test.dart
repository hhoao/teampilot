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

  group('WorkspaceLandingProjectResolver', () {
    test('resolveSelectedProjectPath prefers stored path when valid', () {
      final resolver = WorkspaceLandingProjectResolver(
        workspace: workspace,
        storedProjectPath: '/extra',
      );
      expect(resolver.resolveSelectedProjectPath(), '/extra');
    });

    test('resolveSelectedProjectPath falls back to first folder option', () {
      final resolver = WorkspaceLandingProjectResolver(workspace: workspace);
      expect(resolver.resolveSelectedProjectPath(), '/main');
    });

    test('single folder workspace still exposes one project option', () {
      final single = Workspace(
        workspaceId: 'ws-2',
        folders: const [WorkspaceFolder(path: '/only')],
        createdAt: 1,
      );
      final resolver = WorkspaceLandingProjectResolver(workspace: single);
      expect(resolver.options, hasLength(1));
      expect(resolver.options.single.path, '/only');
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
      final resolver = WorkspaceLandingProjectResolver(
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

  group('WorkspaceLandingWorktreeResolver', () {
    test('resolveSelectedWorktreePath prefers stored path when valid', () {
      final resolver = WorkspaceLandingWorktreeResolver(
        projectPath: '/repo',
        storedWorktreePath: '/repo/.worktrees/feature',
        worktreeState: WorktreeState(
          repoPath: '/repo',
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
          currentWorktreePath: '/repo',
        ),
      );
      expect(
        resolver.resolveSelectedWorktreePath(),
        '/repo/.worktrees/feature',
      );
    });

    test('falls back to project root when no worktrees are known', () {
      final resolver = WorkspaceLandingWorktreeResolver(projectPath: '/solo');
      expect(resolver.options.single.path, '/solo');
      expect(resolver.resolveSelectedWorktreePath(), '/solo');
    });

    test('hides worktree selector for non-git folders', () {
      final resolver = WorkspaceLandingWorktreeResolver(
        projectPath: '/plain',
        worktreeState: const WorktreeState(
          repoPath: '/plain',
          worktrees: [],
          loading: false,
        ),
      );
      expect(resolver.showsWorktreeSelector, isFalse);
    });

    test('shows worktree selector when git worktrees are known', () {
      final resolver = WorkspaceLandingWorktreeResolver(
        projectPath: '/repo',
        worktreeState: WorktreeState(
          repoPath: '/repo',
          worktrees: [
            GitWorktree(
              path: '/repo',
              branch: 'refs/heads/main',
              head: 'abc',
              isBare: false,
              isMainWorktree: true,
            ),
          ],
        ),
      );
      expect(resolver.showsWorktreeSelector, isTrue);
    });

    test('hides worktree selector while worktree list is loading', () {
      final resolver = WorkspaceLandingWorktreeResolver(
        projectPath: '/repo',
        worktreeState: const WorktreeState(
          repoPath: '/repo',
          worktrees: [],
          loading: true,
        ),
      );
      expect(resolver.showsWorktreeSelector, isFalse);
    });
  });
}
