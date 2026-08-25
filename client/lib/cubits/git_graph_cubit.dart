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
    _errorSurfaced = true;
    emit(state.copyWith(errorMessage: message));
  }

  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _loadMoreInFlight = false;

  Future<void> setRepoRoot(String root) async {
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
      final rows = await _history.graphRows(
        dir,
        query: state.searchQuery,
        mode: state.searchMode,
      );
      final status = await _git.status(dir);
      if (isClosed || state.repoRoot != dir) return;
      final branches = await _history.branches(dir);
      final tags = await _history.tags(dir);
      final stashes = await _history.stashList(dir);
      if (isClosed || state.repoRoot != dir) return;
      final keepSurfacedError = _errorSurfaced;
      _errorSurfaced = false;
      emit(
        state.copyWith(
          rows: rows,
          hasMore: rows.length == GitHistoryService.initialLoadCommits,
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
}
