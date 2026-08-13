import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/worktree_branch_options.dart';
import 'package:teampilot/services/git/worktree_create_result.dart';

void main() {
  const options = [
    WorktreeBranchOption.local('main'),
    WorktreeBranchOption.local('feat/x'),
    WorktreeBranchOption.fromRemote(
      name: 'feature/expert-hub',
      remoteRef: 'origin/feature/expert-hub',
    ),
  ];

  WorktreeCreateResult build({
    String branch = 'feat/x-wt',
    String selectorText = '',
  }) => buildWorktreeCreateResult(
    branch: branch,
    selectorText: selectorText,
    options: options,
    worktreePath: '/root/worktrees/repo/feat/x-wt',
  );

  group('buildWorktreeCreateResult', () {
    test('empty selector derives from current HEAD', () {
      final r = build(selectorText: '');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, isNull);
      expect(r.branch, 'feat/x-wt');
    });

    test('custom selector text is used as the base ref', () {
      final r = build(branch: 'hotfix', selectorText: 'v1.2.0');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'v1.2.0');
      expect(r.branch, 'hotfix');
    });

    test('local branch X with name X checks out X', () {
      final r = build(branch: 'feat/x', selectorText: 'feat/x');
      expect(r.existingBranch, isTrue);
      expect(r.baseRef, isNull);
      expect(r.branch, 'feat/x');
    });

    test('local branch X with a different name derives from X', () {
      final r = build(branch: 'feat/x-wt', selectorText: 'feat/x');
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'feat/x');
      expect(r.branch, 'feat/x-wt');
    });

    test('remote-only branch derives from its remote ref', () {
      final r = build(
        branch: 'feature/expert-hub',
        selectorText: 'origin/feature/expert-hub',
      );
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'origin/feature/expert-hub');
      expect(r.branch, 'feature/expert-hub');
    });

    test('remote-only branch with a different name derives', () {
      final r = build(
        branch: 'hub-work',
        selectorText: 'origin/feature/expert-hub',
      );
      expect(r.existingBranch, isFalse);
      expect(r.baseRef, 'origin/feature/expert-hub');
      expect(r.branch, 'hub-work');
    });

    test('empty branch name throws ArgumentError', () {
      expect(
        () => build(branch: '  '),
        throwsArgumentError,
      );
    });
  });

  group('worktreeOptionForLabel', () {
    test('matches local and remote-only by display label', () {
      expect(
        worktreeOptionForLabel(options, 'feat/x')?.name,
        'feat/x',
      );
      expect(
        worktreeOptionForLabel(options, 'origin/feature/expert-hub')?.remoteRef,
        'origin/feature/expert-hub',
      );
    });

    test('returns null for unknown or empty labels', () {
      expect(worktreeOptionForLabel(options, 'main/other'), isNull);
      expect(worktreeOptionForLabel(options, ''), isNull);
    });
  });
}
