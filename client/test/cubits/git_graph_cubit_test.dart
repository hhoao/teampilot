import 'dart:async';

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

  test('refresh completing after loadMore keeps the appended rows', () async {
    // 竞态：refresh 发起时快照 300 行；等待期间 loadMore 追加完成；
    // refresh 随后才 emit——不得用过期的第一页覆盖累计结果。
    var releaseLoadMore = Completer<List<GitGraphRow>>();
    final history = _RacyHistory(
      // 满页首屏（300 条）才有 hasMore=true，loadMore 才会真正发起。
      firstPage: List<GitGraphRow>.generate(
        GitHistoryService.initialLoadCommits,
        (i) => graphCommitRow('p$i'),
      ),
      morePage: [graphCommitRow('h3'), graphCommitRow('h4')],
      gateLoadMore: releaseLoadMore.future,
    );
    final cubit = GitGraphCubit(history: history, git: FakeGitForGraph(repoStatus()));
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');

    final loadMoreDone = cubit.loadMore();
    final refreshDone = cubit.refresh();
    releaseLoadMore.complete([
      graphCommitRow('h3'),
      graphCommitRow('h4'),
    ]);
    await loadMoreDone;
    await refreshDone;

    expect(
      cubit.state.rows.length,
      GitHistoryService.initialLoadCommits + 2,
      reason: 'refresh 完成于 loadMore 之后，不得覆盖追加结果',
    );
    expect((cubit.state.rows.last as GitCommitRow).hash, 'h4');
  });

  test('poll refresh keeps accumulated pagination when head unchanged',
      () async {
    final history = _ScriptedHistory(
      expandToLimit: true,
      pages: [
        [graphCommitRow('h1'), graphCommitRow('h2')], // 首屏（扩充到满页）
        [graphCommitRow('h3'), graphCommitRow('h4')], // loadMore 追加
        [graphCommitRow('h1'), graphCommitRow('h2')], // 轮询重取第一页（头未变）
      ],
    );
    final cubit = GitGraphCubit(history: history, git: FakeGitForGraph(repoStatus()));
    await cubit.setRepoRoot('/repo');
    await cubit.loadMore();
    expect(cubit.state.rows.length, GitHistoryService.initialLoadCommits + GitHistoryService.loadMoreCommits);
    await cubit.refresh(); // 模拟后台轮询
    expect(
      cubit.state.rows.length,
      GitHistoryService.initialLoadCommits + GitHistoryService.loadMoreCommits,
      reason: '轮询不得重置已累计的分页',
    );
    expect((cubit.state.rows.last as GitCommitRow).hash, 'h4');
    expect(cubit.state.hasMore, isTrue);
    await cubit.close();
  });

  test('graph spacer rows do not break pagination flags or skip math',
      () async {
    // --graph 输出含 merge 连线行：总行数 > 提交数。hasMore 必须按
    // 「提交数 == limit」判定，skip 也必须按提交数递增。
    final history = SpacedFullPagesHistory();
    final cubit = GitGraphCubit(history: history, git: FakeGitForGraph(repoStatus()));
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');

    final pageCommits = GitHistoryService.initialLoadCommits;
    expect(
      cubit.state.rows.whereType<GitCommitRow>().length,
      pageCommits,
    );
    expect(cubit.state.rows.length, greaterThan(pageCommits)); // 含 spacer
    expect(cubit.state.hasMore, isTrue, reason: '满页提交 + spacer 行也应视为还有更多');

    await cubit.loadMore();
    expect(history.lastArgs['skip'], pageCommits,
        reason: 'skip 按「已加载提交数」而非总行数');
    expect(
      cubit.state.rows.whereType<GitCommitRow>().length,
      pageCommits + GitHistoryService.loadMoreCommits,
    );
    expect(cubit.state.hasMore, isTrue);
  });

  test('refresh replaces rows when head commit changed', () async {
    final history = _ScriptedHistory(pages: [
      [graphCommitRow('h1'), graphCommitRow('h2')],
      [graphCommitRow('x9'), graphCommitRow('h1')], // 上游来了新提交 → 整页替换
    ]);
    final cubit = GitGraphCubit(history: history, git: FakeGitForGraph(repoStatus()));
    await cubit.setRepoRoot('/repo');
    await cubit.refresh();
    expect((cubit.state.rows.first as GitCommitRow).hash, 'x9');
    expect(cubit.state.rows.length, 2);
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

  test('setBranchFilter scopes refresh and loadMore to that branch', () async {
    final history = FakeHistoryForGraph(
      rows: [graphCommitRow('c1')],
      fullPages: true,
    );
    final cubit = GitGraphCubit(
      history: history,
      git: FakeGitForGraph(repoStatus()),
    );
    await cubit.setRepoRoot('/repo');
    expect(history.lastArgs['revisionRange'], isNull);
    await cubit.setBranchFilter('feature/x');
    expect(cubit.state.branchFilter, 'feature/x');
    expect(history.lastArgs['revisionRange'], 'feature/x');
    await cubit.loadMore();
    expect(history.lastArgs['revisionRange'], 'feature/x');
    expect(history.lastArgs['skip'], GitHistoryService.initialLoadCommits);
    await cubit.close();
  });

  test(
    'clearing branch filter restores scope default; toggle clears filter',
    () async {
      final history = FakeHistoryForGraph(rows: [graphCommitRow('c1')]);
      final cubit = GitGraphCubit(
        history: history,
        git: FakeGitForGraph(repoStatus()),
      );
      await cubit.setRepoRoot('/repo');
      await cubit.setBranchFilter('feature/x');
      await cubit.setBranchFilter(null);
      expect(cubit.state.branchFilter, isNull);
      expect(history.lastArgs['revisionRange'], isNull); // currentOnly=false

      // 过滤优先级高于范围开关；切换范围时清除过滤。
      await cubit.setBranchFilter('feature/x');
      await cubit.setShowOnlyCurrentBranch(!cubit.state.currentOnly);
      expect(cubit.state.currentOnly, isTrue);
      expect(cubit.state.branchFilter, isNull);
      expect(history.lastArgs['revisionRange'], 'HEAD');
      await cubit.close();
    },
  );

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


/// 按调用序返回不同页面的 fake：验证分页与轮询刷新的交互。
class _ScriptedHistory implements GitHistoryService {
  _ScriptedHistory({required this.pages, this.expandToLimit = false});

  /// 为真时把每页循环填充到请求的 limit（模拟大仓库的满页返回）。
  final bool expandToLimit;

  /// 每次 `graphRows` 调用按序消耗一页；耗尽后重复最后一页。
  final List<List<GitGraphRow>> pages;
  int calls = 0;
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
    String? revisionRange,
  }) async {
    lastArgs = {'skip': skip, 'revisionRange': revisionRange};
    final i = calls < pages.length ? calls : pages.length - 1;
    calls++;
    final page = pages[i];
    if (!expandToLimit) return page;
    if (page.isEmpty || limit <= 0) return page;
    // 保持页首为该页 HEAD，其余循环填充至满页。
    return List<GitGraphRow>.generate(limit, (n) => page[n % page.length]);
  }

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => const [];

  @override
  Future<List<GitTagInfo>> tags(String dir) async => const [];

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}


/// 可控时序的 fake：loadMore 的结果由 [gateLoadMore] 门控，用于复现
/// 「refresh 与 loadMore 并发、且 refresh 后完成」的竞态。
class _RacyHistory implements GitHistoryService {
  _RacyHistory({
    required this.firstPage,
    required this.morePage,
    required this.gateLoadMore,
  });

  final List<GitGraphRow> firstPage;
  final List<GitGraphRow> morePage;
  final Future<List<GitGraphRow>> gateLoadMore;
  int loadMoreCalls = 0;

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
  }) {
    if (skip == 0) return Future.value(firstPage);
    loadMoreCalls++;
    return gateLoadMore;
  }

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => const [];

  @override
  Future<List<GitTagInfo>> tags(String dir) async => const [];

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}
