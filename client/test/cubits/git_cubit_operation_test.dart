import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/git_operation.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Scriptable [GitService] that never spawns a process.
class _GatedGitService extends GitService {
  _GatedGitService({GitRepoStatus? status}) : _status = status ?? _repoStatus();

  static GitRepoStatus _repoStatus() => GitRepoStatus(
    isRepository: true,
    branch: 'main',
    hasCommits: true,
    staged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true),
    ],
  );

  GitRepoStatus _status;
  final List<String> calls = [];
  Completer<void>? pushGate;
  Completer<void>? pullGate;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async {
    calls.add('status');
    return _status;
  }

  @override
  Future<void> push(String dir) async {
    calls.add('push');
    final gate = pushGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> pull(String dir) async {
    calls.add('pull');
    final gate = pullGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> fetchAll(String dir) async {
    calls.add('fetchAll');
  }
}

void main() {
  late _GatedGitService service;
  late GitCubit cubit;

  setUp(() async {
    service = _GatedGitService();
    cubit = GitCubit(service: service, minOperationVisible: Duration.zero);
    await cubit.setRepoRoot('/repo');
    service.calls.clear();
  });

  tearDown(() async {
    await cubit.close();
  });

  test('push publishes its operation, refreshes, then clears it', () async {
    final seen = <GitOperation?>[];
    final sub = cubit.stream.listen((state) => seen.add(state.operation));

    service.pushGate = Completer<void>();
    final future = cubit.push();
    expect(cubit.state.operation, GitOperation.push);
    expect(cubit.state.busy, isTrue);

    service.pushGate!.complete();
    await future;

    expect(cubit.state.operation, isNull);
    expect(cubit.state.busy, isFalse);
    expect(service.calls, containsAllInOrder(['push', 'status']));
    expect(seen, contains(GitOperation.push));
    await sub.cancel();
  });

  test('a second mutating op is rejected while one is in flight', () async {
    service.pushGate = Completer<void>();
    final push = cubit.push();
    final pulled = await cubit.pull();

    expect(pulled, isFalse);
    expect(service.calls.where((c) => c == 'pull'), isEmpty);
    expect(cubit.state.operation, GitOperation.push);

    service.pushGate!.complete();
    await push;
    expect(cubit.state.operation, isNull);
  });

  test('background refresh does not publish an operation', () async {
    final seen = <GitOperation?>[];
    final sub = cubit.stream.listen((state) => seen.add(state.operation));

    await cubit.refresh();

    expect(seen, isNot(contains(GitOperation.refresh)));
    expect(cubit.state.operation, isNull);
    await sub.cancel();
  });

  test('manual refresh publishes the refresh operation', () async {
    final future = cubit.refresh(manual: true);

    // Published synchronously, before the first git subprocess returns.
    expect(cubit.state.operation, GitOperation.refresh);

    await future;
    expect(cubit.state.operation, isNull);
  });
}
