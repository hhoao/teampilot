import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_worktree.dart';

void main() {
  test('shortBranch strips refs/heads/ prefix', () {
    const wt = GitWorktree(
      path: '/repo',
      branch: 'refs/heads/feat/x',
      head: 'abc123',
      isBare: false,
      isMainWorktree: true,
    );
    expect(wt.shortBranch, 'feat/x');
    expect(wt.isDetached, false);
  });

  test('detached worktree (empty branch) shows short head', () {
    const wt = GitWorktree(
      path: '/repo',
      branch: '',
      head: 'abcdef1234567890',
      isBare: false,
      isMainWorktree: false,
    );
    expect(wt.isDetached, true);
    expect(wt.shortBranch, 'abcdef1');
  });
}
