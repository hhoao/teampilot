import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/worktree_branch_options.dart';

void main() {
  group('mergeWorktreeBranchOptions', () {
    test('lists local branches and remote-only refs', () {
      final options = mergeWorktreeBranchOptions(
        local: ['main', 'feat/notifications'],
        remote: [
          'origin/main',
          'origin/feature/expert-hub',
          'origin/HEAD',
        ],
      );

      expect(options, [
        const WorktreeBranchOption.local('main'),
        const WorktreeBranchOption.local('feat/notifications'),
        const WorktreeBranchOption.fromRemote(
          name: 'feature/expert-hub',
          remoteRef: 'origin/feature/expert-hub',
        ),
      ]);
    });

    test('skips remote refs that already have a local branch', () {
      final options = mergeWorktreeBranchOptions(
        local: ['main'],
        remote: ['origin/main', 'upstream/main'],
      );

      expect(options, [const WorktreeBranchOption.local('main')]);
    });
  });

  group('suggestWorktreeBranchName', () {
    test('appends -wt to the current branch', () {
      expect(suggestWorktreeBranchName('main'), 'main-wt');
      expect(suggestWorktreeBranchName('feat/x'), 'feat/x-wt');
    });

    test('falls back when branch is empty', () {
      expect(suggestWorktreeBranchName(null), 'worktree');
      expect(suggestWorktreeBranchName(''), 'worktree');
      expect(suggestWorktreeBranchName('  '), 'worktree');
    });
  });
}
