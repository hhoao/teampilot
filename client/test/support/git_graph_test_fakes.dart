import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_history_actions.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart';

/// [GitHistoryService] 测试替身：固定 graph 行与提交详情，记录调用参数。
class FakeHistoryForGraph implements GitHistoryService {
  FakeHistoryForGraph({
    this.rows = const [],
    this.detail,
    this.fileDiff =
        'diff --git a/a.dart b/a.dart\n'
        '--- a/a.dart\n'
        '+++ b/a.dart\n'
        '@@ -1 +1 @@\n'
        '-a\n'
        '+b\n',
    this.fullPages = false,
    this.branchInfos = const [],
    this.tagInfos = const [],
  });

  final List<GitGraphRow> rows;
  final GitCommitDetail? detail;

  /// `commitFileDiff` 返回的固定 diff 文本。
  final String fileDiff;

  /// 为真时按请求的 limit 循环填满每页，模拟“仍有更多提交”的大仓库。
  final bool fullPages;

  /// `branches` / `tags` 返回的固定列表。
  final List<GitBranchInfo> branchInfos;
  final List<GitTagInfo> tagInfos;

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
    String? revisionRange,
  }) async {
    graphCalls++;
    lastArgs = {
      'limit': limit,
      'skip': skip,
      'query': query,
      'mode': mode,
      'revisionRange': revisionRange,
    };
    if (fullPages) {
      return List<GitGraphRow>.generate(limit, (i) => rows[i % rows.length]);
    }
    return rows;
  }

  @override
  Future<GitCommitDetail> commitDetail(String dir, String hash) async =>
      detail!;

  @override
  Future<String> commitFileDiff(
    String dir, {
    required String hash,
    String? parent,
    required String path,
  }) async => fileDiff;

  @override
  Future<List<GitBranchInfo>> branches(String dir) async => branchInfos;

  @override
  Future<List<GitTagInfo>> tags(String dir) async => tagInfos;

  @override
  Future<List<GitStashEntry>> stashList(String dir) async => const [];
}

/// [GitService] 测试替身：固定 `git status` 结果。
class FakeGitForGraph implements GitService {
  FakeGitForGraph(this.statusResult, {this.diffText = ''});

  final GitRepoStatus statusResult;

  /// `diffAgainstHead` 返回的固定 diff 文本。
  final String diffText;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<GitRepoStatus> status(String dir) async => statusResult;

  @override
  Future<String> diffAgainstHead(
    String dir,
    String relativePath, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
    bool untracked = false,
  }) async => diffText;
}

/// [GitHistoryActions] 录制替身：记录调用并可通过 [throwNext] 注入失败。
class RecordingGraphActions implements GitHistoryActions {
  final List<List<String>> calls = [];
  Object? throwNext;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void _maybeThrow() {
    final t = throwNext;
    if (t != null) throw t;
  }

  @override
  Future<void> createBranchAt(
    String dir,
    String name, {
    required String startPoint,
  }) async {
    calls.add(['branch', name, startPoint]);
    _maybeThrow();
  }

  @override
  Future<void> deleteBranch(
    String dir,
    String name, {
    bool force = false,
  }) async {
    calls.add(['branch', force ? '-D' : '-d', name]);
    _maybeThrow();
  }

  @override
  Future<void> renameBranch(String dir, String oldName, String newName) async {
    calls.add(['rename-branch', oldName, newName]);
    _maybeThrow();
  }

  @override
  Future<void> checkoutBranch(String dir, String name) async {
    calls.add(['checkout-branch', name]);
    _maybeThrow();
  }

  @override
  Future<void> checkoutCommit(String dir, String hash) async {
    calls.add(['checkout-commit', hash]);
    _maybeThrow();
  }

  @override
  Future<void> mergeIntoCurrent(String dir, String refName) async {
    calls.add(['merge', refName]);
    _maybeThrow();
  }

  @override
  Future<void> deleteTag(String dir, String name) async {
    calls.add(['delete-tag', name]);
    _maybeThrow();
  }

  @override
  Future<void> pushTag(String dir, String name, {String remote = 'origin'}) async {
    calls.add(['push-tag', name, remote]);
    _maybeThrow();
  }

  @override
  Future<void> resetTo(
    String dir,
    String ref, {
    required GitResetMode mode,
  }) async {
    calls.add([
      'reset',
      switch (mode) {
        GitResetMode.soft => '--soft',
        GitResetMode.mixed => '--mixed',
        GitResetMode.hard => '--hard',
      },
      ref,
    ]);
    _maybeThrow();
  }

  @override
  Future<void> cherryPick(String dir, String hash) async {
    calls.add(['cherry-pick', hash]);
    _maybeThrow();
  }
}

GitCommitRow graphCommitRow(
  String hash, {
  List<GitRefDecoration> refs = const [],
}) => GitCommitRow(
  edges: const [GitGraphEdge(0, 0, 0)],
  node: const GitGraphNode(0, 0),
  hash: hash,
  parents: const ['p0'],
  authorName: 'A',
  authorEmail: 'a@x',
  authorDate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  subject: 's-$hash',
  refs: refs,
);

GitRepoStatus repoStatus() => GitRepoStatus(
  isRepository: true,
  branch: 'main',
  upstream: 'origin/main',
  ahead: 1,
  behind: 0,
  hasCommits: true,
);

/// 有暂存与未暂存改动的状态（dirtyCount = 2）。
GitRepoStatus dirtyStatus() => const GitRepoStatus(
  isRepository: true,
  branch: 'main',
  upstream: 'origin/main',
  ahead: 0,
  behind: 0,
  hasCommits: true,
  staged: [
    GitFileChange(path: 'a.dart', kind: GitChangeKind.modified, staged: true),
  ],
  unstaged: [
    GitFileChange(path: 'b.dart', kind: GitChangeKind.modified, staged: false),
  ],
);

/// 不在 git 工作树内的目录状态。
GitRepoStatus notRepoStatus() =>
    const GitRepoStatus(isRepository: false, hasCommits: false);
