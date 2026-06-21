import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/utils/session_worktree_grouping.dart';

GitWorktree _wt(String path, {bool main = false}) => GitWorktree(
      path: path,
      branch: 'refs/heads/${path.split('/').last}',
      head: 'h',
      isBare: false,
      isMainWorktree: main,
    );

AppSession _session(String id, String primary) =>
    AppSession(sessionId: id, workspaceId: 'w', primaryPath: primary, createdAt: 0);

void main() {
  final worktrees = [_wt('/repo', main: true), _wt('/wt/feat')];

  test('longest-prefix match buckets sessions into their worktree', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('a', '/repo'), _session('b', '/wt/feat')],
    );
    expect(groups.first.worktree!.isMainWorktree, true);
    expect(groups.first.sessions.single.sessionId, 'a');
    expect(groups[1].sessions.single.sessionId, 'b');
  });

  test('a session inside a nested worktree path is matched by longest prefix', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('c', '/wt/feat/sub/dir')],
    );
    // /wt/feat is a prefix of /wt/feat/sub/dir; /repo is not.
    final featGroup = groups.firstWhere((g) => g.worktree?.path == '/wt/feat');
    expect(featGroup.sessions.single.sessionId, 'c');
  });

  test('empty worktree still produces an empty group', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('a', '/repo')],
    );
    expect(groups[1].sessions, isEmpty);
    expect(groups[1].worktree!.shortBranch, 'feat');
  });

  test('unmatched session falls into the orphan group (worktree == null)', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('z', '/gone/dir')],
    );
    final orphan = groups.last;
    expect(orphan.worktree, isNull);
    expect(orphan.isOrphan, true);
    expect(orphan.sessions.single.sessionId, 'z');
  });

  test('no orphan group when all sessions match', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('a', '/repo')],
    );
    expect(groups.any((g) => g.isOrphan), false);
  });

  test('main group sorts first; orphan group sorts last', () {
    final groups = groupSessionsByWorktree(
      worktrees: worktrees,
      sessions: [_session('z', '/gone'), _session('a', '/repo')],
    );
    expect(groups.first.worktree!.isMainWorktree, true);
    expect(groups.last.worktree, isNull);
  });
}
