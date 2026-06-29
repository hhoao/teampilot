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
    expect(cubit.state.changesTreeView.stagedRows, isEmpty);
    expect(cubit.state.changesTreeView.unstagedRows, isEmpty);
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
      cubit.state.changesTreeView.unstagedRows.map(
        (r) => r.isFolder ? 'D:${r.name}' : 'F:${r.change!.path}',
      ),
      ['D:src', 'F:src/foo.dart'],
    );

    await cubit.close();
  });

  test('stage calls service then refreshes', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.stage(_unstaged);

    expect(service.calls, ['stage', 'status']);
    expect(service.stagedPaths, [
      ['b.txt'],
    ]);
    await cubit.close();
  });

  test('stageFolder passes directory path to service', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.stageFolder('docs');

    expect(service.calls, ['stage', 'status']);
    expect(service.stagedPaths, [
      ['docs'],
    ]);
    await cubit.close();
  });

  test('unstageFolder passes directory path to service', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.unstageFolder('src/utils');

    expect(service.calls, ['unstage', 'status']);
    expect(service.unstagedPaths, [
      ['src/utils'],
    ]);
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

  test('commit is a no-op when nothing is staged', () async {
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
    await cubit.setRepoRoot('/repo');
    cubit.setCommitMessage('hello');
    service.calls.clear();

    final ok = await cubit.commit();

    expect(ok, isTrue);
    expect(service.calls, ['commit:hello', 'status']);
    expect(cubit.state.commitMessage, '');
    await cubit.close();
  });

  test('mutation failure surfaces an error message', () async {
    final service = _FakeGitService(statusToReturn: _repoWith())
      ..throwOnNext = GitException('boom');
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');

    await cubit.stage(_unstaged);

    expect(cubit.state.errorMessage, 'boom');
    expect(cubit.state.busy, isFalse);
    await cubit.close();
  });

  test('toggleExpandAllFolders expands then collapses change folders', () async {
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
  });

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
