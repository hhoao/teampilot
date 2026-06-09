import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Records calls and returns scripted status; never spawns a process.
class _FakeGitService extends GitService {
  _FakeGitService({required this.statusToReturn})
    : super(runner: (exe, args, {stdoutEncoding, stderrEncoding}) async {
        throw StateError('runner should not be used in fake');
      });

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
  Future<List<String>> branches(String dir) async => ['main', 'dev'];

  Future<void> _record(String op) async {
    calls.add(op);
    final err = throwOnNext;
    if (err != null) {
      throwOnNext = null;
      throw err;
    }
  }

  @override
  Future<void> stage(String dir, List<String> paths) => _record('stage');

  @override
  Future<void> unstage(String dir, List<String> paths) => _record('unstage');

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
  test('setRepoRoot refreshes status and branches', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);

    await cubit.setRepoRoot('/repo');

    expect(cubit.state.repoRoot, '/repo');
    expect(cubit.state.isRepository, isTrue);
    expect(cubit.state.branches, ['main', 'dev']);
    expect(service.calls, contains('status'));
    await cubit.close();
  });

  test('stage calls service then refreshes', () async {
    final service = _FakeGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();

    await cubit.stage(_unstaged);

    expect(service.calls, ['stage', 'status']);
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

  test('refresh after close does not throw', () async {
    final service = _SlowGitService(statusToReturn: _repoWith());
    final cubit = GitCubit(service: service);
    final refreshFuture = cubit.setRepoRoot('/repo');
    await cubit.close();
    await refreshFuture;
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
