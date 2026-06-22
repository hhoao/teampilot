import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/git/git_worktree_service.dart';
import 'package:teampilot/services/git/worktree_removal.dart';

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'w',
  folders: const [WorkspaceFolder(path: '/wt')],
  createdAt: 0,
);

class _FakeWorktreeService extends GitWorktreeService {
  _FakeWorktreeService(this._onRemove);

  final void Function({
    required String repoPath,
    required String worktreePath,
    required bool force,
    String? deleteBranch,
  }) _onRemove;

  @override
  Future<void> remove(
    String repoPath,
    String worktreePath, {
    bool force = false,
    String? deleteBranch,
  }) async {
    _onRemove(
      repoPath: repoPath,
      worktreePath: worktreePath,
      force: force,
      deleteBranch: deleteBranch,
    );
  }
}

void main() {
  const wt = GitWorktree(
    path: '/wt/feat',
    branch: 'refs/heads/feat/x',
    head: 'abc',
    isBare: false,
    isMainWorktree: false,
  );

  test('removeWorktreeWithSessions deletes sessions only when requested', () async {
    var removed = false;
    final deleted = <String>[];
    final service = _FakeWorktreeService(({
      required repoPath,
      required worktreePath,
      required force,
      deleteBranch,
    }) {
      removed = true;
      expect(repoPath, '/repo');
      expect(worktreePath, '/wt/feat');
      expect(force, false);
      expect(deleteBranch, isNull);
    });

    await removeWorktreeWithSessions(
      service: service,
      repoPath: '/repo',
      worktreePath: '/wt/feat',
      worktree: wt,
      options: const WorktreeDeleteOptions(
        force: false,
        deleteBranch: false,
        deleteSessions: false,
      ),
      sessionsInGroup: [_session('a'), _session('b')],
      deleteSession: (id) async => deleted.add(id),
    );

    expect(removed, true);
    expect(deleted, isEmpty);
  });

  test('removeWorktreeWithSessions cascades session delete and branch -d', () async {
    final deleted = <String>[];
    final service = _FakeWorktreeService(({
      required repoPath,
      required worktreePath,
      required force,
      deleteBranch,
    }) {
      expect(force, true);
      expect(deleteBranch, 'feat/x');
    });

    await removeWorktreeWithSessions(
      service: service,
      repoPath: '/repo',
      worktreePath: '/wt/feat',
      worktree: wt,
      options: const WorktreeDeleteOptions(
        force: true,
        deleteBranch: true,
        deleteSessions: true,
      ),
      sessionsInGroup: [_session('a'), _session('b')],
      deleteSession: (id) async => deleted.add(id),
    );

    expect(deleted, ['a', 'b']);
  });
}
