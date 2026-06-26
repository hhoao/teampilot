import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/services/workspace/workspace_worktree_registry.dart';
import 'package:teampilot/services/workspace/workspace_worktree_store.dart';

GitWorktree _wt(String path, {bool main = false}) => GitWorktree(
      path: path,
      branch: 'refs/heads/main',
      head: 'abc1234',
      isBare: false,
      isMainWorktree: main,
    );

void main() {
  group('WorkspaceWorktreeStore', () {
    test('remember and peek round-trip per workspace repo', () {
      final store = WorkspaceWorktreeStore();
      final list = [_wt('/repo', main: true), _wt('/repo/wt-a')];
      store.remember('ws-1', '/repo', list);

      final snap = store.peek('ws-1', '/repo');
      expect(snap, isNotNull);
      expect(snap!.worktrees, hasLength(2));
      expect(snap.worktrees.first.path, '/repo');
    });

    test('removeWorkspace drops all repo keys for that workspace', () {
      final store = WorkspaceWorktreeStore();
      store.remember('ws-1', '/repo-a', [_wt('/repo-a', main: true)]);
      store.remember('ws-1', '/repo-b', [_wt('/repo-b', main: true)]);
      store.remember('ws-2', '/other', [_wt('/other', main: true)]);

      store.removeWorkspace('ws-1');

      expect(store.peek('ws-1', '/repo-a'), isNull);
      expect(store.peek('ws-1', '/repo-b'), isNull);
      expect(store.peek('ws-2', '/other'), isNotNull);
    });
  });

  group('WorktreeSidebarView.sessionListLayout', () {
    test('empty + loading is indeterminate', () {
      final view = WorktreeSidebarView.from(
        const WorktreeState(loading: true),
      );
      expect(view.sessionListLayout, WorktreeSessionListLayout.indeterminate);
    });

    test('cached multiple worktrees while loading stays grouped', () {
      final view = WorktreeSidebarView.from(
        WorktreeState(
          worktrees: [_wt('/repo', main: true), _wt('/wt')],
          loading: true,
        ),
      );
      expect(view.sessionListLayout, WorktreeSessionListLayout.grouped);
    });

    test('single worktree when ready is flat', () {
      final view = WorktreeSidebarView.from(
        WorktreeState(worktrees: [_wt('/repo', main: true)]),
      );
      expect(view.sessionListLayout, WorktreeSessionListLayout.flat);
    });
  });

  group('WorkspaceWorktreeRegistry', () {
    test('reuses cubit for the same workspace id', () {
      final registry = WorkspaceWorktreeRegistry();
      final a = registry.cubitFor(workspaceId: 'ws-1', repoPath: '/repo');
      final b = registry.cubitFor(workspaceId: 'ws-1', repoPath: '/repo');
      expect(identical(a, b), isTrue);
      registry.dispose();
    });

    test('hydrates cubit from store snapshot on first create', () {
      final registry = WorkspaceWorktreeRegistry();
      registry.store.remember(
        'ws-1',
        '/repo',
        [_wt('/repo', main: true), _wt('/wt')],
      );
      final cubit = registry.cubitFor(workspaceId: 'ws-1', repoPath: '/repo');
      expect(cubit.state.worktrees, hasLength(2));
      expect(
        WorktreeSidebarView.from(cubit.state).sessionListLayout,
        WorktreeSessionListLayout.grouped,
      );
      registry.dispose();
    });
  });
}
