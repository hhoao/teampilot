import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart';

import '../support/git_graph_test_fakes.dart';

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
    String? revisionRange,
  }) async {
    calls++;
    if (calls > 1) throw GitException('boom');
    return [graphCommitRow('c$calls')];
  }

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => const [];

  @override
  Future<List<GitTagInfo>> tags(String dir) async => const [];

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}

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

void main() {
  test('setRepoRoot loads first page + metadata', () async {
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c1')],
      detail: null,
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    expect((cubit.state.rows.single as GitCommitRow).hash, 'c1');
    expect(cubit.state.currentBranch, 'main');
    expect(cubit.state.ahead, 1);
    expect(cubit.state.hasMore, isFalse); // 1 行 < limit 300
    await cubit.close();
  });

  test('loadMore requests skip=rows.length and appends', () async {
    // fullPages: 首屏与 loadMore 都返回满页，验证 hasMore = 行数 == limit。
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c0'), graphCommitRow('c1')],
      detail: null,
      fullPages: true,
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await cubit.loadMore();
    expect(history.lastArgs['skip'], GitHistoryService.initialLoadCommits);
    expect(
      cubit.state.rows.length,
      GitHistoryService.initialLoadCommits + GitHistoryService.loadMoreCommits,
    );
    expect(cubit.state.hasMore, isTrue); // loadMore 满页 → 视为还有更多
    await cubit.close();
  });

  test('selectCommit lazily loads detail; null clears selection', () async {
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c1')],
      detail: _detailFor('c1'),
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
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
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('abc12')],
      detail: null,
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    await cubit.search('fix', GitSearchMode.message);
    expect(history.lastArgs['query'], 'fix');
    expect(history.lastArgs['mode'], GitSearchMode.message);
    expect(cubit.state.visibleRows, hasLength(1));
    await cubit.close();
  });

  test(
    'hash mode filters loaded rows client-side; clearSearch restores',
    () async {
      final history = FakeHistoryForGraph(
        rows: [graphCommitRow('abcdef1'), graphCommitRow('1234567')],
        detail: null,
      );
      final cubit = GitGraphCubit(
        history: history,
        git: FakeGitForGraph(repoStatus()),
      );
      await cubit.setRepoRoot('/repo');
      await cubit.search('abc', GitSearchMode.hash);
      expect((cubit.state.visibleRows.single as GitCommitRow).hash, 'abcdef1');
      await cubit.clearSearch();
      expect(cubit.state.visibleRows, hasLength(2));
      await cubit.close();
    },
  );

  test('service error lands in errorMessage without losing rows', () async {
    final failing = _FailingHistory();
    final cubit = GitGraphCubit(
      history: failing,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/ok'); // 第一次成功载入 1 行
    await cubit.refresh(); // 第二次 graphRows 抛 GitException
    expect(cubit.state.errorMessage, isNotNull);
    expect(cubit.state.rows, isNotEmpty); // 旧行保留
    await cubit.close();
  });

  test('surfaceError after close is a no-op', () async {
    final cubit = GitGraphCubit(
      history: FakeHistoryForGraph(rows: [graphCommitRow('c1')]),
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.close();
    // 关闭后再调用不得抛出 emit-after-close 异常。
    cubit.surfaceError('boom');
  });
}
