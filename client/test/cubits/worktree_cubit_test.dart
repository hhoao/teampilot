import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';
import 'package:teampilot/services/home_workspace/worktree_ui_prefs_store.dart';
import 'package:teampilot/services/workspace/workspace_worktree_store.dart';

import '../support/in_memory_filesystem.dart';

class _FakeWorktreeService implements WorktreeLister {
  _FakeWorktreeService(this._list);
  List<GitWorktree> _list;
  @override
  Future<List<GitWorktree>> list(String repoPath) async => _list;
}

class _CountingLister implements WorktreeLister {
  _CountingLister(this._listFor);
  final List<GitWorktree> Function(String repoPath) _listFor;
  var calls = 0;
  final listedPaths = <String>[];

  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    calls++;
    listedPaths.add(repoPath);
    return _listFor(repoPath);
  }
}

class _StubGitWorktreeService extends GitWorktreeService {
  _StubGitWorktreeService(this._worktrees) : super();
  final List<GitWorktree> _worktrees;

  @override
  Future<List<GitWorktree>> list(String repoPath) async => _worktrees;
}

class _DelayedLister implements WorktreeLister {
  _DelayedLister(this._list, this.delay);
  final List<GitWorktree> _list;
  final Duration delay;

  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    await Future<void>.delayed(delay);
    return _list;
  }
}

class _DelayedPrefsStore extends WorktreeUiPrefsStore {
  _DelayedPrefsStore({required this.delay, super.fs, super.pathOverride});
  final Duration delay;

  @override
  Future<WorktreeUiPref?> prefsFor(String workspaceId) async {
    await Future<void>.delayed(delay);
    return super.prefsFor(workspaceId);
  }
}

GitWorktree _wt(String p, {bool main = false}) => GitWorktree(
  path: p,
  branch: 'refs/heads/x',
  head: 'h',
  isBare: false,
  isMainWorktree: main,
);

void main() {
  test('load without lister throws StateError', () {
    final cubit = WorktreeCubit();
    expect(cubit.load('/repo'), throwsA(isA<StateError>()));
  });

  test(
    'bindWorktreeService loads worktrees and honors preferCurrentPath',
    () async {
      final cubit = WorktreeCubit();
      cubit.bindWorktreeService(
        _StubGitWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]),
        repoPath: '/repo',
        preferCurrentPath: '/wt/a/lib/main.dart',
      );
      await cubit.stream.firstWhere(
        (s) => !s.loading && s.worktrees.isNotEmpty,
      );
      expect(cubit.state.worktrees, hasLength(2));
      expect(cubit.state.currentWorktreePath, '/wt/a');
    },
  );

  test(
    'deferred bindWorktreeService unblocks a waiter then selectProject',
    () async {
      // Compose landing waits for the tools-scope bind (loading→false) before
      // selectProject; the early local GitWorktreeService() bind is gone.
      final cubit = WorktreeCubit(
        workspaceId: 'w1',
        initialRepoPath: '/remote/repo',
      );
      expect(cubit.state.loading, isTrue);

      final firstLoadDone = cubit.stream.firstWhere((s) => !s.loading);
      cubit.bindWorktreeService(
        _StubGitWorktreeService([
          _wt('/remote/repo', main: true),
          _wt('/remote/wt'),
        ]),
        repoPath: '/remote/repo',
      );
      await firstLoadDone;

      await cubit.selectProject('/remote/repo');
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.worktrees, hasLength(2));
    },
  );

  test('hydration runs in parallel with git list on first load', () async {
    final svc = _DelayedLister([
      _wt('/repo', main: true),
      _wt('/wt/a'),
    ], const Duration(milliseconds: 30));
    final store = _DelayedPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs/worktree-ui-prefs.json',
      delay: const Duration(milliseconds: 30),
    );
    final cubit = WorktreeCubit(
      lister: svc,
      workspaceId: 'w1',
      prefsStore: store,
    );
    final started = DateTime.now();
    await cubit.load('/repo');
    final elapsed = DateTime.now().difference(started);
    expect(cubit.state.worktrees, hasLength(2));
    expect(elapsed.inMilliseconds, lessThan(55));
  });

  test(
    'load populates worktrees and defaults current to first (main)',
    () async {
      final svc = _FakeWorktreeService([
        _wt('/repo', main: true),
        _wt('/wt/a'),
      ]);
      final cubit = WorktreeCubit(lister: svc);
      await cubit.load('/repo');
      expect(cubit.state.worktrees, hasLength(2));
      expect(cubit.state.currentWorktreePath, '/repo');
      expect(cubit.state.hasMultipleWorktrees, true);
    },
  );

  test('hasMultipleWorktrees is false with a single worktree', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true)]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    expect(cubit.state.hasMultipleWorktrees, false);
  });

  test('setCurrentWorktree switches current path', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.setCurrentWorktree('/wt/a');
    expect(cubit.state.currentWorktreePath, '/wt/a');
  });

  test('reload preserves current selection when it still exists', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.setCurrentWorktree('/wt/a');
    await cubit.load('/repo'); // reload
    expect(cubit.state.currentWorktreePath, '/wt/a');
  });

  test('reload falls back to first when current selection vanished', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.setCurrentWorktree('/wt/a');
    svc._list = [_wt('/repo', main: true)]; // /wt/a removed
    await cubit.load('/repo');
    expect(cubit.state.currentWorktreePath, '/repo');
  });

  test('toggleCollapsed flips a worktree collapse flag', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.toggleCollapsed('/wt/a');
    expect(cubit.state.collapsed.contains('/wt/a'), true);
    cubit.toggleCollapsed('/wt/a');
    expect(cubit.state.collapsed.contains('/wt/a'), false);
  });

  test('load uses preferCurrentPath to pick the containing worktree', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo', preferCurrentPath: '/wt/a/lib/main.dart');
    expect(cubit.state.currentWorktreePath, '/wt/a');
  });

  test(
    'syncCurrentForSessionPath updates current to the containing worktree',
    () async {
      final svc = _FakeWorktreeService([
        _wt('/repo', main: true),
        _wt('/wt/a'),
      ]);
      final cubit = WorktreeCubit(lister: svc);
      await cubit.load('/repo');
      cubit.syncCurrentForSessionPath('/wt/a/src/foo.dart');
      expect(cubit.state.currentWorktreePath, '/wt/a');
    },
  );

  test(
    'syncCurrentForSessionPath is a no-op for orphan session paths',
    () async {
      final svc = _FakeWorktreeService([_wt('/repo', main: true)]);
      final cubit = WorktreeCubit(lister: svc);
      await cubit.load('/repo');
      cubit.syncCurrentForSessionPath('/gone/dir');
      expect(cubit.state.currentWorktreePath, '/repo');
    },
  );

  test('persists collapse + current and rehydrates on a fresh cubit', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final store = WorktreeUiPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs/worktree-ui-prefs.json',
    );
    final c1 = WorktreeCubit(lister: svc, workspaceId: 'w1', prefsStore: store);
    await c1.load('/repo');
    c1.setCurrentWorktree('/wt/a');
    c1.toggleCollapsed('/wt/a');
    await Future<void>.delayed(Duration.zero); // let fire-and-forget save flush

    final c2 = WorktreeCubit(lister: svc, workspaceId: 'w1', prefsStore: store);
    await c2.load('/repo');
    expect(c2.state.currentWorktreePath, '/wt/a');
    expect(c2.state.collapsed.contains('/wt/a'), true);
  });

  test('pathForNewSession is null with a single worktree', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true)]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    expect(cubit.state.pathForNewSession, isNull);
  });

  test(
    'pathForNewSession follows current worktree when multiple exist',
    () async {
      final svc = _FakeWorktreeService([
        _wt('/repo', main: true),
        _wt('/wt/a'),
      ]);
      final cubit = WorktreeCubit(lister: svc);
      await cubit.load('/repo');
      expect(cubit.state.pathForNewSession, '/repo');
      cubit.setCurrentWorktree('/wt/a');
      expect(cubit.state.pathForNewSession, '/wt/a');
    },
  );

  test('stale load completion is ignored when a newer load finishes', () async {
    final lister = _RepoDelayedLister();
    final cubit = WorktreeCubit(lister: lister);
    final slow = cubit.load('/repo-a');
    final fast = cubit.load('/repo-b');
    cubit.setCurrentWorktree('/repo-b/wt');
    await Future.wait([slow, fast]);
    expect(cubit.state.repoPath, '/repo-b');
    expect(cubit.state.currentWorktreePath, '/repo-b/wt');
    expect(cubit.state.worktrees, hasLength(2));
  });

  test(
    'selectProject skips git list when the same repo is already loaded',
    () async {
      final lister = _CountingLister((_) => const []);
      final cubit = WorktreeCubit(lister: lister);
      await cubit.load('/Documents/TeamPilot');
      expect(lister.calls, 1);
      expect(cubit.state.worktrees, isEmpty);

      await cubit.selectProject(
        '/Documents/TeamPilot',
        preferWorktreePath: '/Documents/TeamPilot/src',
      );
      expect(lister.calls, 1);
      expect(cubit.state.loading, isFalse);
      expect(cubit.state.repoPath, '/Documents/TeamPilot');
      expect(cubit.state.currentWorktreePath, '/Documents/TeamPilot');
    },
  );

  test(
    'load reuses remembered empty (non-git) snapshot without calling git',
    () async {
      final store = WorkspaceWorktreeStore();
      final lister = _CountingLister((_) => const []);
      final first = WorktreeCubit(
        lister: lister,
        workspaceId: 'ws-1',
        worktreeStore: store,
      );
      await first.load('/Documents/TeamPilot');
      expect(lister.calls, 1);
      expect(store.peek('ws-1', '/Documents/TeamPilot'), isNotNull);
      expect(store.peek('ws-1', '/Documents/TeamPilot')!.worktrees, isEmpty);
      await first.close();

      final second = WorktreeCubit(
        lister: lister,
        workspaceId: 'ws-1',
        worktreeStore: store,
        initialRepoPath: '/Documents/TeamPilot',
      );
      expect(second.state.repoPath, '/Documents/TeamPilot');
      await second.load('/Documents/TeamPilot');
      expect(lister.calls, 1);
      expect(second.state.loading, isFalse);
      expect(second.state.worktrees, isEmpty);
      await second.close();
    },
  );

  test(
    'load with force re-lists from git even when the store has a snapshot',
    () async {
      final store = WorkspaceWorktreeStore();
      final lister = _FakeWorktreeService([_wt('/repo', main: true)]);
      final cubit = WorktreeCubit(
        lister: lister,
        workspaceId: 'ws-1',
        worktreeStore: store,
      );
      await cubit.load('/repo');
      expect(cubit.state.worktrees, hasLength(1));

      // A worktree was created on disk by git; the cached snapshot is stale.
      lister._list = [_wt('/repo', main: true), _wt('/wt/a')];
      await cubit.load('/repo', force: true);
      expect(cubit.state.worktrees, hasLength(2));
      expect(store.peek('ws-1', '/repo')!.worktrees, hasLength(2));
    },
  );

  test(
    'selectProject still lists when switching to a different project',
    () async {
      final lister = _CountingLister((path) {
        if (path == '/repo-a') return [_wt('/repo-a', main: true)];
        return const [];
      });
      final cubit = WorktreeCubit(lister: lister);
      await cubit.load('/repo-a');
      expect(lister.calls, 1);

      await cubit.selectProject('/Documents/TeamPilot');
      expect(lister.calls, 2);
      expect(cubit.state.repoPath, '/Documents/TeamPilot');
      expect(cubit.state.worktrees, isEmpty);
    },
  );

  test(
    'selectProject applies preferWorktreePath without re-listing',
    () async {
      final lister = _CountingLister(
        (_) => [_wt('/repo', main: true), _wt('/wt/a')],
      );
      final cubit = WorktreeCubit(lister: lister);
      await cubit.load('/repo');
      expect(cubit.state.currentWorktreePath, '/repo');
      expect(lister.calls, 1);

      await cubit.selectProject('/repo', preferWorktreePath: '/wt/a/lib/x.dart');
      expect(lister.calls, 1);
      expect(cubit.state.currentWorktreePath, '/wt/a');
    },
  );
}

class _RepoDelayedLister implements WorktreeLister {
  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    if (repoPath == '/repo-a') {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return [_wt('/repo-a', main: true)];
    }
    return [_wt('/repo-b', main: true), _wt('/repo-b/wt')];
  }
}
