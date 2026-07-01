import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';
import 'package:teampilot/services/home_workspace/worktree_ui_prefs_store.dart';

import '../support/in_memory_filesystem.dart';

class _FakeWorktreeService implements WorktreeLister {
  _FakeWorktreeService(this._list);
  List<GitWorktree> _list;
  @override
  Future<List<GitWorktree>> list(String repoPath) async => _list;
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
    path: p, branch: 'refs/heads/x', head: 'h', isBare: false, isMainWorktree: main);

void main() {
  test('load without lister throws StateError', () {
    final cubit = WorktreeCubit();
    expect(cubit.load('/repo'), throwsA(isA<StateError>()));
  });

  test('bindWorktreeService loads worktrees and honors preferCurrentPath', () async {
    final cubit = WorktreeCubit();
    cubit.bindWorktreeService(
      _StubGitWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]),
      repoPath: '/repo',
      preferCurrentPath: '/wt/a/lib/main.dart',
    );
    await cubit.stream.firstWhere((s) => !s.loading && s.worktrees.isNotEmpty);
    expect(cubit.state.worktrees, hasLength(2));
    expect(cubit.state.currentWorktreePath, '/wt/a');
  });

  test('hydration runs in parallel with git list on first load', () async {
    final svc = _DelayedLister(
      [_wt('/repo', main: true), _wt('/wt/a')],
      const Duration(milliseconds: 30),
    );
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

  test('load populates worktrees and defaults current to first (main)', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    expect(cubit.state.worktrees, hasLength(2));
    expect(cubit.state.currentWorktreePath, '/repo');
    expect(cubit.state.hasMultipleWorktrees, true);
  });

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

  test('syncCurrentForSessionPath updates current to the containing worktree', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.syncCurrentForSessionPath('/wt/a/src/foo.dart');
    expect(cubit.state.currentWorktreePath, '/wt/a');
  });

  test('syncCurrentForSessionPath is a no-op for orphan session paths', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true)]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    cubit.syncCurrentForSessionPath('/gone/dir');
    expect(cubit.state.currentWorktreePath, '/repo');
  });

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

  test('pathForNewSession follows current worktree when multiple exist', () async {
    final svc = _FakeWorktreeService([_wt('/repo', main: true), _wt('/wt/a')]);
    final cubit = WorktreeCubit(lister: svc);
    await cubit.load('/repo');
    expect(cubit.state.pathForNewSession, '/repo');
    cubit.setCurrentWorktree('/wt/a');
    expect(cubit.state.pathForNewSession, '/wt/a');
  });
}
