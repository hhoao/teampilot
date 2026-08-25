import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart';

class _FakeHistory implements GitHistoryService {
  _FakeHistory({
    required this.rows,
    this.detail,
    this.fullPages = false,
  });

  final List<GitGraphRow> rows;
  final GitCommitDetail? detail;

  /// 为真时按请求的 limit 循环填满每页，模拟“仍有更多提交”的大仓库。
  final bool fullPages;

  int graphCalls = 0;
  Map<String, Object?> lastArgs = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<GitGraphRow>> graphRows(
    String dir, {
    int limit = GitHistoryService.initialLoadCommits,
    int skip = 0,
    String query = '',
    GitSearchMode mode = GitSearchMode.message,
  }) async {
    graphCalls++;
    lastArgs = {'limit': limit, 'skip': skip, 'query': query, 'mode': mode};
    if (fullPages) {
      return List<GitGraphRow>.generate(limit, (i) => rows[i % rows.length]);
    }
    return rows;
  }

  @override
  Future<GitCommitDetail> commitDetail(String dir, String hash) async =>
      detail!;

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => const [];

  @override
  Future<List<GitTagInfo>> tags(String dir) async => const [];

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}

class _FakeGit implements GitService {
  _FakeGit(this.statusResult);

  final GitRepoStatus statusResult;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<GitRepoStatus> status(String dir) async => statusResult;
}

class _FailingHistory implements GitHistoryService {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<GitGraphRow>> graphRows(
    String dir, {
    int limit = GitHistoryService.initialLoadCommits,
    int skip = 0,
    String query = '',
    GitSearchMode mode = GitSearchMode.message,
  }) async {
    calls++;
    if (calls > 1) throw GitException('boom');
    return [commitRow('c$calls')];
  }

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => const [];

  @override
  Future<List<GitTagInfo>> tags(String dir) async => const [];

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}

GitCommitRow commitRow(String hash) => GitCommitRow(
      edges: const [GitGraphEdge(0, 0, 0)],
      node: const GitGraphNode(0, 0),
      hash: hash,
      parents: const ['p0'],
      authorName: 'A',
      authorEmail: 'a@x',
      authorDate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      subject: 's-$hash',
      refs: const [],
    );

GitCommitDetail _detailFor(String hash) => GitCommitDetail(
      hash: hash,
      parents: const ['p0'],
      authorName: 'A',
      authorEmail: 'a@x',
      authorDate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      subject: 's-$hash',
      body: '',
      files: const [],
    );

GitRepoStatus repoStatus({bool dirty = false}) => GitRepoStatus(
      isRepository: true,
      branch: 'main',
      upstream: 'origin/main',
      ahead: 1,
      behind: 0,
      staged: dirty
          ? const [
              GitFileChange(
                path: 'a.dart',
                kind: GitChangeKind.modified,
                staged: true,
              ),
            ]
          : const [],
    );

void main() {
  test('setRepoRoot loads first page + metadata', () async {
    final history = _FakeHistory(rows: [commitRow('c1')], detail: null);
    final cubit = GitGraphCubit(history: history, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/repo');
    expect((cubit.state.rows.single as GitCommitRow).hash, 'c1');
    expect(cubit.state.currentBranch, 'main');
    expect(cubit.state.ahead, 1);
    expect(cubit.state.hasMore, isFalse); // 1 行 < limit 300
    await cubit.close();
  });

  test('loadMore requests skip=rows.length and appends', () async {
    // fullPages: 首屏与 loadMore 都返回满页，验证 hasMore = 行数 == limit。
    final history = _FakeHistory(
      rows: [commitRow('c0'), commitRow('c1')],
      detail: null,
      fullPages: true,
    );
    final cubit = GitGraphCubit(history: history, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/repo');
    await cubit.loadMore();
    expect(
      history.lastArgs['skip'],
      GitHistoryService.initialLoadCommits,
    );
    expect(
      cubit.state.rows.length,
      GitHistoryService.initialLoadCommits + GitHistoryService.loadMoreCommits,
    );
    expect(cubit.state.hasMore, isTrue); // loadMore 满页 → 视为还有更多
    await cubit.close();
  });

  test('selectCommit lazily loads detail; null clears selection', () async {
    final history =
        _FakeHistory(rows: [commitRow('c1')], detail: _detailFor('c1'));
    final cubit = GitGraphCubit(history: history, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/repo');
    cubit.selectCommit('c1');
    await cubit.stream.firstWhere((s) => s.commitDetail != null);
    expect(cubit.state.commitDetail!.hash, 'c1');
    cubit.selectCommit(null);
    expect(cubit.state.selectedHash, isNull);
    expect(cubit.state.commitDetail, isNull);
    await cubit.close();
  });

  test('search message mode passes query server-side', () async {
    final history = _FakeHistory(rows: [commitRow('abc12')], detail: null);
    final cubit = GitGraphCubit(history: history, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/repo');
    await cubit.search('fix', GitSearchMode.message);
    expect(history.lastArgs['query'], 'fix');
    expect(history.lastArgs['mode'], GitSearchMode.message);
    expect(cubit.state.visibleRows, hasLength(1));
    await cubit.close();
  });

  test('hash mode filters loaded rows client-side; clearSearch restores',
      () async {
    final history = _FakeHistory(
        rows: [commitRow('abcdef1'), commitRow('1234567')], detail: null);
    final cubit = GitGraphCubit(history: history, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/repo');
    await cubit.search('abc', GitSearchMode.hash);
    expect(
        (cubit.state.visibleRows.single as GitCommitRow).hash, 'abcdef1');
    await cubit.clearSearch();
    expect(cubit.state.visibleRows, hasLength(2));
    await cubit.close();
  });

  test('service error lands in errorMessage without losing rows', () async {
    final failing = _FailingHistory();
    final cubit = GitGraphCubit(history: failing, git: _FakeGit(repoStatus()));
    await cubit.setRepoRoot('/ok'); // 第一次成功载入 1 行
    await cubit.refresh(); // 第二次 graphRows 抛 GitException
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.rows, isNotEmpty); // 旧行保留
    await cubit.close();
  });
}
