import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Records calls and returns scripted status; never spawns a process.
class _FakeGitService extends GitService {
  _FakeGitService({required this.statusToReturn}) : super();

  GitRepoStatus statusToReturn;
  final List<String> calls = [];
  GitException? throwOnNext;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async {
    calls.add('status');
    return statusToReturn;
  }

  @override
  Future<List<String>> branches(String dir) async {
    calls.add('branches');
    return ['main', 'dev'];
  }

  Future<void> _record(String op) async {
    calls.add(op);
    final err = throwOnNext;
    if (err != null) {
      throwOnNext = null;
      throw err;
    }
  }

  @override
  Future<void> commit(String dir, String message) => _record('commit:$message');

  final List<List<String>> commitSelectedCalls = [];

  @override
  Future<void> commitSelected(String dir, String message, List<String> paths) async {
    commitSelectedCalls.add(['add', '--', ...paths]);
    commitSelectedCalls.add(['commit', '-m', message, '--', ...paths]);
  }

  final List<List<String>> commitAmendCalls = [];

  @override
  Future<void> commitAmend(String dir, String message, List<String> paths) async {
    commitAmendCalls.add([message, ...paths]);
  }

  final List<String> discardAllCalls = [];
  final List<List<String>> discardFolderCalls = [];
  final List<List<GitFileChange>> discardFolderChanges = [];

  @override
  Future<void> discardAll(String dir) async {
    discardAllCalls.add(dir);
    await _record('discardAll');
  }

  @override
  Future<void> discardFolder(
    String dir,
    String folderPath, {
    List<GitFileChange> changes = const [],
  }) async {
    discardFolderCalls.add([dir, folderPath]);
    discardFolderChanges.add(changes);
    await _record('discardFolder');
  }
}

GitRepoStatus _repoWith({
  List<GitFileChange> staged = const [],
  List<GitFileChange> unstaged = const [],
}) {
  return GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: staged,
    unstaged: unstaged,
  );
}

const _staged = GitFileChange(
  path: 'a.txt',
  kind: GitChangeKind.modified,
  staged: true,
);
const _unstaged = GitFileChange(
  path: 'b.txt',
  kind: GitChangeKind.modified,
  staged: false,
);

void main() {
  test('setRepoRoot refreshes status only; branches load lazily', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);

    await cubit.setRepoRoot('/repo');

    expect(cubit.state.repoRoot, '/repo');
    expect(cubit.state.isRepository, isTrue);
    expect(cubit.state.changesTreeView.rows, isEmpty);
    expect(cubit.state.changesTreeView.selectedCount, 0);
    expect(cubit.state.changesTreeView.totalCount, 0);
    expect(service.calls, contains('status'));
    expect(cubit.state.branches, isEmpty);
    expect(service.calls, isNot(contains('branches')));

    await cubit.ensureBranches();
    expect(cubit.state.branches, ['main', 'dev']);
    expect(service.calls, contains('branches'));

    await cubit.close();
  });

  test('changesTreeView is precomputed after status load', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          GitFileChange(
            path: 'src/foo.dart',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    expect(
      cubit.state.changesTreeView.rows.map(
        (r) => r.isFolder ? 'D:${r.name}' : 'F:${r.change!.path}',
      ),
      ['D:src', 'F:src/foo.dart'],
    );

    await cubit.close();
  });

  test('selectFolder selects every changed path under the folder', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged, // b.txt
          GitFileChange(
            path: 'docs/a.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          GitFileChange(
            path: 'docs/b.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    await cubit.selectNone(GitChangesSection.changes); // clear the auto-selection first
    await cubit.selectFolder('docs', GitChangesSection.changes);

    expect(cubit.state.selectedPaths, {'docs/a.txt', 'docs/b.txt'});
    await cubit.close();
  });

  test('deselectFolder clears every selected path under the folder', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged, // b.txt
          GitFileChange(
            path: 'docs/a.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          GitFileChange(
            path: 'docs/b.txt',
            kind: GitChangeKind.modified,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // all auto-selected

    await cubit.deselectFolder('docs', GitChangesSection.changes);

    expect(cubit.state.selectedPaths, {'b.txt'});
    await cubit.close();
  });

  test('discardAll runs git restore . and refreshes', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.discardAll();

    expect(service.discardAllCalls, ['/repo']);
    expect(service.calls, ['discardAll', 'status']);
    await cubit.close();
  });

  test('discardFolder passes folder path and changes under it', () async {
    const tracked = GitFileChange(
      path: 'src/utils/a.txt',
      kind: GitChangeKind.modified,
      staged: false,
    );
    const untracked = GitFileChange(
      path: 'src/utils/b.txt',
      kind: GitChangeKind.untracked,
      staged: false,
    );
    const other = GitFileChange(
      path: 'docs/c.txt',
      kind: GitChangeKind.modified,
      staged: false,
    );
    final service = _FakeGitService(
      statusToReturn: _repoWith(unstaged: const [tracked, untracked, other]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.discardFolder('src/utils');

    expect(service.discardFolderCalls, [
      ['/repo', 'src/utils'],
    ]);
    expect(service.discardFolderChanges.single, [tracked, untracked]);
    expect(service.calls, ['discardFolder', 'status']);
    await cubit.close();
  });

  test('commit is a no-op when message is blank', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(staged: const [_staged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isFalse);
    expect(service.calls, isEmpty);
    await cubit.close();
  });

  test('commit is a no-op when nothing is selected', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setCommitMessage('hello');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isFalse);
    expect(service.calls, isEmpty);
    await cubit.close();
  });

  test('commit succeeds, clears message, refreshes, and clears the selection',
      () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(staged: const [_staged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // a.txt auto-selected
    cubit.setCommitMessage('hello');
    service.calls.clear();

    // After the commit the tree is clean, so the committed path is gone from
    // the status; the post-commit refresh must drop it from the selection.
    service.statusToReturn = _repoWith();

    final ok = await cubit.commit();

    expect(ok, isTrue);
    expect(service.commitSelectedCalls, [
      ['add', '--', 'a.txt'],
      ['commit', '-m', 'hello', '--', 'a.txt'],
    ]);
    expect(service.calls, contains('status')); // refresh after commit
    expect(cubit.state.commitMessage, '');
    expect(cubit.state.selectedPaths, isEmpty); // committed paths deselected
    await cubit.close();
  });

  test('selectPath/deselectPath only change the selection, never run git', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(unstaged: const [_unstaged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    final unstagedPath = cubit.state.status.unstaged.single.path;
    await cubit.selectPath(_unstaged.path);
    expect(cubit.state.selectedPaths, contains(unstagedPath));
    expect(service.calls, isEmpty); // NO git call

    await cubit.deselectPath(_unstaged.path);
    expect(cubit.state.selectedPaths, isEmpty);
    expect(service.calls, isEmpty);
    await cubit.close();
  });

  test('refresh reconciles selection: new files checked, vanished dropped, manual uncheck kept', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(unstaged: const [_unstaged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // first load: b.txt selected by default
    expect(cubit.state.selectedPaths, {'b.txt'});

    // manual uncheck of b.txt
    await cubit.deselectPath(_unstaged.path);
    expect(cubit.state.selectedPaths, isEmpty);

    // next refresh adds a NEW tracked file c.txt (auto-checked), an index-staged
    // file staged.txt (auto-checked), and a NEW untracked file new.ts (NOT
    // auto-checked). b.txt stays unchecked.
    service.statusToReturn = _repoWith(
      unstaged: const [
        _unstaged,
        GitFileChange(
          path: 'c.txt',
          kind: GitChangeKind.modified,
          staged: false,
        ),
        GitFileChange(
          path: 'new.ts',
          kind: GitChangeKind.untracked,
          staged: false,
        ),
      ],
      staged: const [
        GitFileChange(path: 'staged.txt', kind: GitChangeKind.added, staged: true),
      ],
    );
    await cubit.refresh();
    expect(cubit.state.selectedPaths, {'c.txt', 'staged.txt'});
    await cubit.close();
  });

  test('untracked files are not auto-checked on first load', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged,
          GitFileChange(
            path: 'new.ts',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    expect(cubit.state.selectedPaths, {'b.txt'}); // new.ts NOT selected
    expect(cubit.state.unversionedTreeView.totalCount, 1);
    expect(cubit.state.changesTreeView.totalCount, 1);
    await cubit.close();
  });

  test('selectAll on a section only selects that section', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          _unstaged,
          GitFileChange(
            path: 'new.ts',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // b.txt auto-selected, new.ts not

    await cubit.selectNone(GitChangesSection.changes);
    expect(cubit.state.selectedPaths, isEmpty);

    await cubit.selectAll(GitChangesSection.unversioned);
    expect(cubit.state.selectedPaths, {'new.ts'});

    await cubit.selectAll(GitChangesSection.changes);
    expect(cubit.state.selectedPaths, {'new.ts', 'b.txt'});
    await cubit.close();
  });

  test('selectFolder is scoped to its section', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(
        unstaged: const [
          GitFileChange(
            path: 'docs/a.md',
            kind: GitChangeKind.modified,
            staged: false,
          ),
          GitFileChange(
            path: 'docs/new.md',
            kind: GitChangeKind.untracked,
            staged: false,
          ),
        ],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    await cubit.selectNone(GitChangesSection.changes);
    await cubit.selectNone(GitChangesSection.unversioned);

    await cubit.selectFolder('docs', GitChangesSection.changes);
    expect(cubit.state.selectedPaths, {'docs/a.md'});

    await cubit.selectFolder('docs', GitChangesSection.unversioned);
    expect(cubit.state.selectedPaths, {'docs/a.md', 'docs/new.md'});
    await cubit.close();
  });

  test('commit passes the selected paths to commitSelected', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(staged: const [_staged], unstaged: const [_unstaged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setCommitMessage('msg'); // setCommitMessage 已存在（面板在用）
    await cubit.selectAll(GitChangesSection.changes);
    service.calls.clear();

    final ok = await cubit.commit();
    expect(ok, isTrue);
    expect(service.commitSelectedCalls, [
      ['add', '--', 'a.txt', 'b.txt'],
      ['commit', '-m', 'msg', '--', 'a.txt', 'b.txt'],
    ]);
    await cubit.close();
  });

  test('mutation failure surfaces an error message', () async {
    final service = _FakeGitService(statusToReturn: _repoWith())
      ..throwOnNext = GitException('boom');
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    await cubit.discardAll();

    expect(cubit.state.errorMessage, 'boom');
    expect(cubit.state.busy, isFalse);
    await cubit.close();
  });

  test(
    'toggleExpandAllFolders expands then collapses change folders',
    () async {
      final service = _FakeGitService(
        statusToReturn: _repoWith(
          unstaged: const [
            GitFileChange(
              path: 'src/utils/foo.dart',
              kind: GitChangeKind.modified,
              staged: false,
            ),
          ],
        ),
      );
      final cubit = GitCubit(service: service);
      await cubit.setRepoRoot('/repo');

      cubit.collapseAllFolders();
      expect(cubit.state.expandedFolderPaths, isEmpty);

      cubit.expandAllFolders();
      expect(cubit.state.expandedFolderPaths, {'src', 'src/utils'});
      expect(cubit.state.allChangeFoldersExpanded, isTrue);

      cubit.toggleExpandAllFolders();
      expect(cubit.state.expandedFolderPaths, isEmpty);

      cubit.toggleExpandAllFolders();
      expect(cubit.state.allChangeFoldersExpanded, isTrue);

      await cubit.close();
    },
  );

  test('refresh after close does not throw', () async {
    final service = _SlowGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    final refreshFuture = cubit.setRepoRoot('/repo');
    await cubit.close();
    await refreshFuture;
  });

  test('concurrent ensureBranches share a single git branch call', () async {
    final service = _SlowBranchesGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    // Rapid picker opens while the first load is in flight.
    await Future.wait([
      cubit.ensureBranches(force: true),
      cubit.ensureBranches(force: true),
      cubit.ensureBranches(force: true),
    ]);

    expect(service.calls.where((c) => c == 'branches').length, 1);
    expect(cubit.state.branches, ['main', 'dev']);

    await cubit.close();
  });

  test('concurrent refreshes coalesce into at most one trailing run', () async {
    final service = _SlowGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    // First refresh (via setRepoRoot) is in flight; pile on more calls.
    final first = cubit.setRepoRoot('/repo');
    final second = cubit.refresh();
    final third = cubit.refresh();
    await Future.wait([first, second, third]);

    // The initial run plus a single trailing run that catches up the queued
    // calls — never one status call per refresh().
    final statusCalls = service.calls.where((c) => c == 'status').length;
    expect(statusCalls, 2);

    await cubit.close();
  });

  test('amend with selection stages and amends those paths', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(staged: const [_staged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // a.txt auto-selected
    cubit.setAmend(true);
    cubit.setCommitMessage('fix: amend');
    service.statusToReturn = _repoWith(); // clean after amend
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isTrue);
    expect(service.commitAmendCalls, [
      ['fix: amend', 'a.txt'],
    ]);
    expect(cubit.state.commitMessage, '');
    expect(cubit.state.amend, isTrue); // sticky after success
    await cubit.close();
  });

  test('amend without selection rewrites the message only', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setAmend(true);
    cubit.setCommitMessage('fix typo');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isTrue);
    expect(service.commitAmendCalls, [
      ['fix typo'],
    ]);
    await cubit.close();
  });

  test('amend is a no-op when the repo has no commits yet', () async {
    final service = _FakeGitService(
      statusToReturn: GitRepoStatus(
        isRepository: true,
        branch: 'main',
        hasCommits: false,
        unstaged: const [_unstaged],
      ),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setAmend(true);
    cubit.setCommitMessage('msg');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isFalse);
    expect(service.commitAmendCalls, isEmpty);
    await cubit.close();
  });

  test('amend is a no-op when the message is blank', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(staged: const [_staged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setAmend(true);
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isFalse);
    expect(service.commitAmendCalls, isEmpty);
    await cubit.close();
  });
}

class _SlowGitService extends _FakeGitService {
  _SlowGitService({required super.statusToReturn});

  @override
  Future<GitRepoStatus> status(String dir) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.status(dir);
  }
}

class _SlowBranchesGitService extends _FakeGitService {
  _SlowBranchesGitService({required super.statusToReturn});

  @override
  Future<List<String>> branches(String dir) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.branches(dir);
  }
}
