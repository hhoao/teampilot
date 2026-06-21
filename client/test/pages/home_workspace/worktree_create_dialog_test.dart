import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/worktree_create_dialog.dart';

void main() {
  test('suggestWorktreeBranchName appends -wt to the current branch', () {
    expect(suggestWorktreeBranchName('main'), 'main-wt');
    expect(suggestWorktreeBranchName('feat/x'), 'feat/x-wt');
  });

  test('suggestWorktreeBranchName falls back when branch is empty', () {
    expect(suggestWorktreeBranchName(null), 'worktree');
    expect(suggestWorktreeBranchName(''), 'worktree');
    expect(suggestWorktreeBranchName('  '), 'worktree');
  });
}
