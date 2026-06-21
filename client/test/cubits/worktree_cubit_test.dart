import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';

class _FakeWorktreeService implements WorktreeLister {
  _FakeWorktreeService(this._list);
  List<GitWorktree> _list;
  @override
  Future<List<GitWorktree>> list(String repoPath) async => _list;
}

GitWorktree _wt(String p, {bool main = false}) => GitWorktree(
    path: p, branch: 'refs/heads/x', head: 'h', isBare: false, isMainWorktree: main);

void main() {
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
}
