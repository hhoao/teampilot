import 'dart:math';

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

  group('randomWorktreeBranchName', () {
    test('generates wt-<6 lowercase hex>', () {
      final name = randomWorktreeBranchName(const [], random: Random(42));
      expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(name), isTrue);
    });

    test('never collides with existing path basenames', () {
      final existing = ['/root/worktrees/repo/wt-a1b2c3', '/w/other-dir'];
      for (var seed = 0; seed < 500; seed++) {
        final name = randomWorktreeBranchName(existing, random: Random(seed));
        expect(name, isNot('wt-a1b2c3'));
        expect(RegExp(r'^wt-[0-9a-f]{6}$').hasMatch(name), isTrue);
      }
    });

    test('falls back to wt-<n> when attempts are exhausted', () {
      expect(
        randomWorktreeBranchName(const [], random: Random(0), maxAttempts: 0),
        'wt-2',
      );
      expect(
        randomWorktreeBranchName(
          ['/w/wt-2', '/w/wt-3'],
          random: Random(0),
          maxAttempts: 0,
        ),
        'wt-4',
      );
    });
  });
}
