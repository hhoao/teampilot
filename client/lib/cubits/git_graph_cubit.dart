import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../models/git_graph.dart';
import '../services/git/git_history_actions.dart';
import '../services/git/git_history_service.dart';
import '../services/git/git_service.dart' show GitException, GitService;
import '../utils/logging/logger.dart';

class GitGraphState extends Equatable {
  const GitGraphState({
    this.repoRoot = '',
    this.rows = const [],
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.selectedHash,
    this.commitDetail,
    this.detailLoading = false,
    this.openFilePath,
    this.fileDiffText,
    this.fileDiffLoading = false,
    this.branches = const [],
    this.tags = const [],
    this.stashList = const [],
    this.currentBranch = '',
    this.ahead = 0,
    this.behind = 0,
    this.dirtyCount = 0,
    this.searchQuery = '',
    this.searchMode = GitSearchMode.message,
    this.currentOnly = false,
    this.branchFilter,
    this.errorMessage,
    this.gitAvailable = true,
  });

  final String repoRoot;
  final List<GitGraphRow> rows;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isRefreshing;
  final String? selectedHash;
  final GitCommitDetail? commitDetail;
  final bool detailLoading;
  final String? openFilePath;
  final String? fileDiffText;
  final bool fileDiffLoading;
  final List<GitBranchInfo> branches;
  final List<GitTagInfo> tags;
  final List<GitStashEntry> stashList;
  final String currentBranch;
  final int ahead;
  final int behind;
  final int dirtyCount;
  final String searchQuery;
  final GitSearchMode searchMode;

  /// 仅显示当前分支（refresh 时以 `HEAD` 替代 `--all`）。
  final bool currentOnly;

  /// 查看指定分支历史（revisionRange 直接用该 ref）；null = 未过滤。
  final String? branchFilter;
  final String? errorMessage;
  final bool gitAvailable;

  static const Object _unset = Object();

  /// 可空字段落支持显式赋值（传值）与命名清空（clearXxx），其余字段直传。
  GitGraphState copyWith({
    String? repoRoot,
    List<GitGraphRow>? rows,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isRefreshing,
    Object? selectedHash = _unset,
    bool clearSelection = false,
    Object? commitDetail = _unset,
    bool clearDetail = false,
    bool? detailLoading,
    Object? openFilePath = _unset,
    Object? fileDiffText = _unset,
    bool clearFileDiff = false,
    bool? fileDiffLoading,
    List<GitBranchInfo>? branches,
    List<GitTagInfo>? tags,
    List<GitStashEntry>? stashList,
    String? currentBranch,
    int? ahead,
    int? behind,
    int? dirtyCount,
    String? searchQuery,
    GitSearchMode? searchMode,
    bool? currentOnly,
    Object? branchFilter = _unset,
    Object? errorMessage = _unset,
    bool clearError = false,
    bool? gitAvailable,
  }) {
    bool isUnset(Object? v) => identical(v, _unset);
    return GitGraphState(
      repoRoot: repoRoot ?? this.repoRoot,
      rows: rows ?? this.rows,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      selectedHash: clearSelection
          ? null
          : isUnset(selectedHash)
          ? this.selectedHash
          : selectedHash as String?,
      commitDetail: clearDetail
          ? null
          : isUnset(commitDetail)
          ? this.commitDetail
          : commitDetail as GitCommitDetail?,
      detailLoading: detailLoading ?? this.detailLoading,
      openFilePath: clearFileDiff
          ? null
          : isUnset(openFilePath)
          ? this.openFilePath
          : openFilePath as String?,
      fileDiffText: clearFileDiff
          ? null
          : isUnset(fileDiffText)
          ? this.fileDiffText
          : fileDiffText as String?,
      fileDiffLoading: fileDiffLoading ?? this.fileDiffLoading,
      branches: branches ?? this.branches,
      tags: tags ?? this.tags,
      stashList: stashList ?? this.stashList,
      currentBranch: currentBranch ?? this.currentBranch,
      ahead: ahead ?? this.ahead,
      behind: behind ?? this.behind,
      dirtyCount: dirtyCount ?? this.dirtyCount,
      searchQuery: searchQuery ?? this.searchQuery,
      searchMode: searchMode ?? this.searchMode,
      currentOnly: currentOnly ?? this.currentOnly,
      branchFilter: isUnset(branchFilter)
          ? this.branchFilter
          : branchFilter as String?,
      errorMessage: clearError
          ? null
          : isUnset(errorMessage)
          ? this.errorMessage
          : errorMessage as String?,
      gitAvailable: gitAvailable ?? this.gitAvailable,
    );
  }

  /// hash 搜索模式对已加载行做前缀过滤（大小写不敏感）；其余模式原样返回 rows。
  List<GitGraphRow> get visibleRows {
    if (searchMode != GitSearchMode.hash || searchQuery.isEmpty) return rows;
    final q = searchQuery.toLowerCase();
    return rows
        .where((r) => r is GitCommitRow && r.hash.toLowerCase().startsWith(q))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [
    repoRoot,
    rows,
    hasMore,
    isLoadingMore,
    isRefreshing,
    selectedHash,
    commitDetail,
    detailLoading,
    openFilePath,
    fileDiffText,
    fileDiffLoading,
    branches,
    tags,
    stashList,
    currentBranch,
    ahead,
    behind,
    dirtyCount,
    searchQuery,
    searchMode,
    currentOnly,
    branchFilter,
    errorMessage,
    gitAvailable,
  ];
}

class GitGraphCubit extends Cubit<GitGraphState> {
  GitGraphCubit({
    required GitHistoryService history,
    required GitService git,
    GitHistoryActions? actions,
  }) : _history = history,
       _git = git,
       _actions = actions ?? GitHistoryActions(),
       super(const GitGraphState());

  final GitHistoryService _history;
  final GitService _git;
  final GitHistoryActions _actions;

  /// [surfaceError] 置位：下一次成功刷新保留该错误一次，再下次才清除。
  bool _errorSurfaced = false;

  @visibleForTesting
  GitHistoryActions get actions => _actions;

  @visibleForTesting
  GitService get gitService => _git;

  /// 写操作失败提示。与刷新自产的错误不同：随后一次成功的 refresh 不清除它，
  /// 避免刚弹出的错误被立刻冲掉；再下次成功刷新（如重试生效）才消失。
  void surfaceError(String message) {
    if (isClosed) return;
    _errorSurfaced = true;
    emit(state.copyWith(errorMessage: message));
  }

  /// 有监听者挂载（面板仍在使用）时不允许被 LRU 淘汰。
  /// GitRepoStore 的淘汰逻辑是合法消费方，故不加 @visibleForTesting。
  bool get hasActiveListeners => _activeListeners.isNotEmpty;

  // bloc 9 的 BlocBase 不再暴露 hasListeners；这里自行维护挂载登记，
  // 回调仅作占位（不接收状态通知），供 GitRepoStore 淘汰逻辑查询。
  final Set<void Function()> _activeListeners = {};

  /// 登记一个占用者（如挂载中的图面板）。
  void addListener(void Function() listener) => _activeListeners.add(listener);

  /// 取消占用登记。
  void removeListener(void Function() listener) =>
      _activeListeners.remove(listener);

  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _loadMoreInFlight = false;

  /// 上次整页拉取的查询签名（query|mode|revisionRange）；变化即视为过滤
  /// 改变，刷新时整页替换而非保留累计分页。
  String _lastFetchSignature = '';

  /// 图查询的 revisionRange：显式分支过滤优先，其次“仅当前分支”（HEAD），
  /// 否则 null（`--all`）。
  String? get _effectiveRevisionRange =>
      state.branchFilter ?? (state.currentOnly ? 'HEAD' : null);

  Future<void> setRepoRoot(String root) async {
    _lastFetchSignature = '';
    emit(GitGraphState(repoRoot: root));
    await refresh();
  }

  Future<void> refresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    try {
      await _runRefresh();
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued && !isClosed) {
        _refreshQueued = false;
        await refresh();
      }
    }
  }

  Future<void> _runRefresh() async {
    final dir = state.repoRoot;
    if (dir.isEmpty || isClosed) return;
    try {
      final signature =
          '${state.searchQuery}|${state.searchMode.index}|$_effectiveRevisionRange';
      final rows = await _history.graphRows(
        dir,
        query: state.searchQuery,
        mode: state.searchMode,
        revisionRange: _effectiveRevisionRange,
      );
      final status = await _git.status(dir);
      if (isClosed || state.repoRoot != dir) return;
      final branches = await _history.branches(dir);
      final tags = await _history.tags(dir);
      final stashes = await _history.stashList(dir);
      if (isClosed || state.repoRoot != dir) return;

      // 轮询/手动重刷只取第一页；若查询条件未变、本地已分页更深且头提交
      // 未变，则保留累计行——否则（新提交到达 / 过滤变化 / 首次加载）
      // 整页替换。
      var nextRows = rows;
      var nextHasMore = rows.length == GitHistoryService.initialLoadCommits;
      final prevRows = state.rows;
      final headUnchanged = rows.isNotEmpty &&
          prevRows.isNotEmpty &&
          _headHashOf(rows) == _headHashOf(prevRows);
      if (_lastFetchSignature == signature &&
          headUnchanged &&
          prevRows.length > rows.length) {
        nextRows = prevRows;
        nextHasMore = state.hasMore;
      }
      _lastFetchSignature = signature;

      final keepSurfacedError = _errorSurfaced;
      _errorSurfaced = false;
      emit(
        state.copyWith(
          rows: nextRows,
          hasMore: nextHasMore,
          branches: branches,
          tags: tags,
          stashList: stashes,
          currentBranch: status.branch ?? '',
          ahead: status.ahead,
          behind: status.behind,
          dirtyCount: status.staged.length + status.unstaged.length,
          gitAvailable: status.isRepository,
          clearError: !keepSurfacedError,
        ),
      );
    } on GitException catch (e) {
      _errorSurfaced = false;
      if (isClosed) return;
      appLogger.e('[GitGraph] refresh failed: ${e.message}');
      emit(state.copyWith(errorMessage: e.message));
    }
  }

  /// 首行（最新提交）的 hash；首行理论上必为 commit，防御 spacer 在前的情况。
  static String _headHashOf(List<GitGraphRow> rows) {
    for (final row in rows) {
      if (row is GitCommitRow) return row.hash;
    }
    return '';
  }

  Future<void> loadMore() async {
    if (_loadMoreInFlight || !state.hasMore || state.isLoadingMore) return;
    _loadMoreInFlight = true;
    emit(state.copyWith(isLoadingMore: true));
    final dir = state.repoRoot;
    try {
      final more = await _history.graphRows(
        dir,
        skip: state.rows.length,
        limit: GitHistoryService.loadMoreCommits,
        query: state.searchQuery,
        mode: state.searchMode,
        revisionRange: _effectiveRevisionRange,
      );
      if (isClosed || state.repoRoot != dir) return;
      emit(
        state.copyWith(
          rows: [...state.rows, ...more],
          hasMore: more.length == GitHistoryService.loadMoreCommits,
          isLoadingMore: false,
        ),
      );
    } on GitException catch (e) {
      _errorSurfaced = false;
      if (isClosed) return;
      appLogger.e('[GitGraph] loadMore failed: ${e.message}');
      emit(state.copyWith(isLoadingMore: false, errorMessage: e.message));
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<void> search(String query, GitSearchMode mode) async {
    emit(state.copyWith(searchQuery: query, searchMode: mode));
    await refresh();
  }

  Future<void> clearSearch() async {
    _errorSurfaced = false;
    emit(state.copyWith(searchQuery: '', clearError: true));
    await refresh();
  }

  /// 分支范围切换：true → 仅当前分支（revisionRange `HEAD`），false → `--all`。
  /// 切换时清除分支历史过滤（两者互斥，过滤优先级更高会掩盖范围切换）。
  Future<void> setShowOnlyCurrentBranch(bool value) async {
    if (state.currentOnly == value && state.branchFilter == null) return;
    emit(state.copyWith(currentOnly: value, branchFilter: null));
    await refresh();
  }

  /// [setShowOnlyCurrentBranch] 的翻转形式。
  void toggleCurrentOnly() {
    unawaited(setShowOnlyCurrentBranch(!state.currentOnly));
  }

  /// 查看指定分支历史：非 null → revisionRange 直接用该 ref（覆盖
  /// currentOnly）；null → 清除过滤，回到范围开关决定的默认。
  Future<void> setBranchFilter(String? ref) async {
    if (state.branchFilter == ref) return;
    emit(state.copyWith(branchFilter: ref));
    await refresh();
  }

  /// null → 清除选中与详情；非 null → 设置并懒加载详情。
  Future<void> selectCommit(String? hash) async {
    final root = state.repoRoot;
    emit(
      state.copyWith(
        selectedHash: hash,
        commitDetail: hash == null ? null : state.commitDetail,
        detailLoading: hash != null,
        clearFileDiff: true,
      ),
    );
    if (hash == null) return;
    try {
      final detail = await _history.commitDetail(root, hash);
      // stale guard：选中项或仓库已变化则丢弃
      if (isClosed || state.selectedHash != hash || state.repoRoot != root) {
        return;
      }
      emit(state.copyWith(commitDetail: detail, detailLoading: false));
    } on GitException catch (e) {
      _errorSurfaced = false;
      if (isClosed) return;
      appLogger.e('[GitGraph] detail failed: ${e.message}');
      emit(state.copyWith(detailLoading: false, errorMessage: e.message));
    }
  }

  Future<void> openCommitFile(GitCommitFileChange file) async {
    final detail = state.commitDetail;
    if (detail == null) return;
    emit(
      state.copyWith(
        openFilePath: file.path,
        fileDiffLoading: true,
        fileDiffText: null,
      ),
    );
    try {
      final text = await _history.commitFileDiff(
        state.repoRoot,
        hash: detail.hash,
        parent: detail.parents.isNotEmpty ? detail.parents.first : null,
        path: file.previousPath ?? file.path,
      );
      if (isClosed || state.openFilePath != file.path) return;
      emit(state.copyWith(fileDiffText: text, fileDiffLoading: false));
    } on GitException catch (e) {
      _errorSurfaced = false;
      if (isClosed) return;
      appLogger.e('[GitGraph] file diff failed: ${e.message}');
      emit(state.copyWith(fileDiffLoading: false, errorMessage: e.message));
    }
  }

  void closeFileDiff() => emit(
    state.copyWith(
      openFilePath: null,
      fileDiffText: null,
      fileDiffLoading: false,
    ),
  );

  /// 整个工作区的未提交 diff（working tree vs HEAD），供未提交伪行打开
  /// changes diff。失败时返回 null（呈现空 diff，不向 UI 抛异常）。
  Future<String?> workingTreeDiff({
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    final dir = state.repoRoot;
    if (dir.isEmpty) return null;
    try {
      // 相对路径 "." 表示仓库根下全部改动，等价于 source control 的逐文件
      // diffAgainstHead，但一次拿到整树。
      return await _git.diffAgainstHead(
        dir,
        '.',
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      );
    } on GitException catch (e) {
      appLogger.e('[GitGraph] working tree diff failed: ${e.message}');
      return null;
    }
  }
}
