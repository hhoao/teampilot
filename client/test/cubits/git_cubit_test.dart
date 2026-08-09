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

  final List<List<String>> stagedPaths = [];
  final List<List<String>> unstagedPaths = [];

  @override
  Future<void> stage(String dir, List<String> paths) async {
    stagedPaths.add(paths);
    await _record('stage');
  }

  @override
  Future<void> unstage(String dir, List<String> paths) async {
    unstagedPaths.add(paths);
    await _record('unstage');
  }

  @override
  Future<void> commit(String dir, String message) => _record('commit:$message');

  final List<List<String>> commitSelectedCalls = [];

  @override
  Future<void> commitSelected(String dir, String message, List<String> paths) async {
    commitSelectedCalls.add(['add', '--', ...paths]);
    commitSelectedCalls.add(['commit', '-m', message, '--', ...paths]);
  }

  final List<String> discardAllCalls = [];
  final List<List<String>> discardFolderCalls = [];

  @override
  Future<void> discardAll(String dir) async {
    discardAllCalls.add(dir);
    await _record('discardAll');
  }

  @override
  Future<void> discardFolder(String dir, String folderPath) async {
    discardFolderCalls.add([dir, folderPath]);
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
    expect(cubit.state.changesTreeView.stagedCount, 0);
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

  test('stageFolder selects every changed path under the folder', () async {
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
    await cubit.unstageAll(); // clear the auto-selection first
    await cubit.stageFolder('docs');

    expect(cubit.state.selectedPaths, {'docs/a.txt', 'docs/b.txt'});
    await cubit.close();
  });

  test('unstageFolder clears every selected path under the folder', () async {
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

    await cubit.unstageFolder('docs');

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

  test('discardFolder passes folder path to service and refreshes', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.discardFolder('src/utils');

    expect(service.discardFolderCalls, [
      ['/repo', 'src/utils'],
    ]);
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

  test('commit succeeds, clears message, and refreshes', () async {
    final service = _FakeGitService(
      statusToReturn: _repoWith(staged: const [_staged]),
    );
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo'); // a.txt auto-selected
    cubit.setCommitMessage('hello');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isTrue);
    expect(service.commitSelectedCalls, [
      ['add', '--', 'a.txt'],
      ['commit', '-m', 'hello', '--', 'a.txt'],
    ]);
    expect(service.calls, contains('status')); // refresh after commit
    expect(cubit.state.commitMessage, '');
    await cubit.close();
  });

  test('stage/unstage only change the selection, never run git', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(unstaged: const [_unstaged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    final unstagedPath = cubit.state.status.unstaged.single.path;
    await cubit.stage(_unstaged);
    expect(cubit.state.selectedPaths, contains(unstagedPath));
    expect(service.calls, isEmpty); // NO git call

    await cubit.unstage(_unstaged);
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
    await cubit.unstage(_unstaged);
    expect(cubit.state.selectedPaths, isEmpty);

    // next refresh adds a NEW file c.txt (auto-checked), b.txt stays unchecked
    service.statusToReturn = _repoWith(
      unstaged: const [_unstaged, GitFileChange(path: 'c.txt', kind: GitChangeKind.modified, staged: false)],
    );
    await cubit.refresh();
    expect(cubit.state.selectedPaths, {'c.txt'});
    await cubit.close();
  });

  test('commit passes the selected paths to commitSelected', () async {
    final service = _FakeGitService(statusToReturn: _repoWith(staged: const [_staged], unstaged: const [_unstaged]));
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    cubit.setCommitMessage('msg'); // setCommitMessage 已存在（面板在用）
    await cubit.stageAll(); // Task 2 阶段方法名仍是 stageAll
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
