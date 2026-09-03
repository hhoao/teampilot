import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_compare_cubit.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart' show GitException;

const _spec = GitCompareSpec(
  repoRoot: '/repo',
  left: GitCompareRef('abc123'),
  right: GitCompareWorkingTree(),
);

const _fileA = GitFileChange(
  path: 'a.dart',
  kind: GitChangeKind.modified,
  staged: false,
);
const _fileB = GitFileChange(
  path: 'b.dart',
  kind: GitChangeKind.untracked,
  staged: false,
);

class _FakeHistory implements GitHistoryService {
  _FakeHistory({
    this.files = const [_fileA],
    this.diffText = 'diff text',
    this.error,
    this.gate,
  });

  List<GitFileChange> files;
  String diffText;
  Object? error;
  Future<void>? gate;

  int listCalls = 0;
  int fileDiffCalls = 0;
  bool? lastUntracked;
  String? lastDiffPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<GitFileChange>> listDiffFiles(
    String dir,
    GitCompareSide from,
    GitCompareSide to,
  ) async {
    listCalls++;
    final g = gate;
    if (g != null) await g;
    final err = error;
    if (err != null) {
      if (err is Exception) throw err;
      throw GitException(err.toString());
    }
    return files;
  }

  @override
  Future<String> fileDiff(
    String dir,
    GitCompareSide from,
    GitCompareSide to,
    String path, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
    bool untracked = false,
  }) async {
    fileDiffCalls++;
    lastUntracked = untracked;
    lastDiffPath = path;
    return diffText;
  }
}

void main() {
  test('load success emits files', () async {
    final history = _FakeHistory(files: const [_fileA, _fileB]);
    final cubit = GitCompareCubit(spec: _spec, history: history);
    addTearDown(cubit.close);

    expect(cubit.state.loading, isFalse);
    final done = cubit.load();
    expect(cubit.state.loading, isTrue);
    await done;

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.files, const [_fileA, _fileB]);
    expect(history.listCalls, 1);
  });

  test('load error emits error string', () async {
    final history = _FakeHistory(error: GitException('boom'));
    final cubit = GitCompareCubit(spec: _spec, history: history);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.error, 'boom');
    expect(cubit.state.files, isEmpty);
  });

  test('stale load does not overwrite newer', () async {
    final gate = Completer<void>();
    final history = _FakeHistory(
      files: const [_fileA],
      gate: gate.future,
    );
    final cubit = GitCompareCubit(spec: _spec, history: history);
    addTearDown(cubit.close);

    final first = cubit.load();
    history.files = const [_fileB];
    history.gate = null;
    await cubit.load();
    expect(cubit.state.files, const [_fileB]);

    gate.complete();
    await first;

    expect(
      cubit.state.files,
      const [_fileB],
      reason: 'stale first load must not overwrite newer result',
    );
    expect(history.listCalls, 2);
  });

  test('refresh aliases load', () async {
    final history = _FakeHistory(files: const [_fileA]);
    final cubit = GitCompareCubit(spec: _spec, history: history);
    addTearDown(cubit.close);

    await cubit.refresh();
    expect(cubit.state.files, const [_fileA]);
    expect(history.listCalls, 1);
  });

  test('toggleFolder and selectPath update state', () {
    final cubit = GitCompareCubit(spec: _spec, history: _FakeHistory());
    addTearDown(cubit.close);

    cubit.toggleFolder('src');
    expect(cubit.state.expandedFolderPaths, {'src'});
    cubit.toggleFolder('src');
    expect(cubit.state.expandedFolderPaths, isEmpty);

    cubit.selectPath('a.dart');
    expect(cubit.state.selectedPath, 'a.dart');
    cubit.selectPath(null);
    expect(cubit.state.selectedPath, isNull);
  });

  test('diffFor passes untracked from file list', () async {
    final history = _FakeHistory(files: const [_fileA, _fileB]);
    final cubit = GitCompareCubit(spec: _spec, history: history);
    addTearDown(cubit.close);
    await cubit.load();

    final tracked = await cubit.diffFor('a.dart', fullContext: true);
    expect(tracked, 'diff text');
    expect(history.lastUntracked, isFalse);
    expect(history.lastDiffPath, 'a.dart');

    final untracked = await cubit.diffFor('b.dart');
    expect(untracked, 'diff text');
    expect(history.lastUntracked, isTrue);
  });
}
