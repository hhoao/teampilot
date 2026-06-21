import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';

void main() {
  group('GitWorktreeService.parseWorktreeList', () {
    test('parses NUL-delimited porcelain blocks; first is main', () {
      const out = 'worktree /repo\x00HEAD abc\x00branch refs/heads/main\x00\x00'
          'worktree /wt/feat\x00HEAD def\x00branch refs/heads/feat/x\x00\x00';
      final list = GitWorktreeService.parseWorktreeList(out, nulDelimited: true);
      expect(list, hasLength(2));
      expect(list[0].path, '/repo');
      expect(list[0].branch, 'refs/heads/main');
      expect(list[0].isMainWorktree, true);
      expect(list[1].path, '/wt/feat');
      expect(list[1].isMainWorktree, false);
    });

    test('parses detached and bare entries', () {
      const out = 'worktree /repo\x00HEAD abc\x00bare\x00\x00'
          'worktree /wt/d\x00HEAD def\x00detached\x00\x00';
      final list = GitWorktreeService.parseWorktreeList(out, nulDelimited: true);
      expect(list[0].isBare, true);
      expect(list[1].branch, '');
      expect(list[1].isDetached, true);
    });

    test('preserves a path containing a space (NUL split, not space split)', () {
      const out = 'worktree /my repo/main\x00HEAD abc\x00branch refs/heads/main\x00\x00';
      final list = GitWorktreeService.parseWorktreeList(out, nulDelimited: true);
      expect(list.single.path, '/my repo/main');
    });

    test('falls back to newline blocks when not NUL-delimited', () {
      const out = 'worktree /repo\nHEAD abc\nbranch refs/heads/main\n\n'
          'worktree /wt/feat\nHEAD def\nbranch refs/heads/feat/x\n';
      final list = GitWorktreeService.parseWorktreeList(out, nulDelimited: false);
      expect(list, hasLength(2));
      expect(list[1].shortBranch, 'feat/x');
    });
  });
}
