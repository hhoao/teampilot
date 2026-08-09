import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ai_feature_setting.dart';
import '../models/git_status.dart';
import '../services/ai/commit_message_prompt.dart';
import '../services/ai/headless_ai_service.dart';
import '../services/git/git_changes_visible_rows.dart';
import '../services/git/git_service.dart';

export '../services/git/git_changes_visible_rows.dart'
    show GitChangesTreeViewData, GitChangesVisibleRow;

class GitState extends Equatable {
  const GitState({
    this.repoRoot = '',
    this.gitAvailable = true,
    this.isLoading = false,
    this.busy = false,
    this.status = GitRepoStatus.notARepository,
    this.commitMessage = '',
    this.branches = const [],
    this.errorMessage,
    this.expandedFolderPaths = const {},
    this.selectedPaths = const {},
    this.generatingCommitMessage = false,
    this.changesTreeView = const GitChangesTreeViewData(
      rows: [],
      stagedCount: 0,
      totalCount: 0,
    ),
  });

  final String repoRoot;
  final bool gitAvailable;
  final bool isLoading;

  /// True while a mutating op (stage/commit/push/…) is running.
  final bool busy;
  final GitRepoStatus status;
  final String commitMessage;
  final List<String> branches;
  final String? errorMessage;
  final Set<String> expandedFolderPaths;

  /// Paths included in the next commit (IDEA-style selection model: checkbox
  /// = include). Pure UI state, reconciled against the status on refresh.
  final Set<String> selectedPaths;
  final bool generatingCommitMessage;

  /// Flattened staged/unstaged rows for the changes tree (recomputed in cubit).
  final GitChangesTreeViewData changesTreeView;

  bool get isRepository => status.isRepository;

  /// True when every folder in the changes tree is expanded.
  bool get allChangeFoldersExpanded {
    final all = gitChangesAllFolderPaths([
      ...status.staged,
      ...status.unstaged,
    ]);
    return all.isNotEmpty && all.every(expandedFolderPaths.contains);
  }

  GitState copyWith({
    String? repoRoot,
    bool? gitAvailable,
    bool? isLoading,
    bool? busy,
    GitRepoStatus? status,
    String? commitMessage,
    List<String>? branches,
    String? errorMessage,
    Set<String>? expandedFolderPaths,
    Set<String>? selectedPaths,
    bool? generatingCommitMessage,
    GitChangesTreeViewData? changesTreeView,
    bool clearError = false,
  }) {
    return GitState(
      repoRoot: repoRoot ?? this.repoRoot,
      gitAvailable: gitAvailable ?? this.gitAvailable,
      isLoading: isLoading ?? this.isLoading,
      busy: busy ?? this.busy,
      status: status ?? this.status,
      commitMessage: commitMessage ?? this.commitMessage,
      branches: branches ?? this.branches,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      expandedFolderPaths: expandedFolderPaths ?? this.expandedFolderPaths,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      generatingCommitMessage:
          generatingCommitMessage ?? this.generatingCommitMessage,
      changesTreeView: changesTreeView ?? this.changesTreeView,
    );
  }

  @override
  List<Object?> get props => [
    repoRoot,
    gitAvailable,
    isLoading,
    busy,
    status,
    commitMessage,
    branches,
    errorMessage,
    expandedFolderPaths,
    selectedPaths,
    generatingCommitMessage,
    changesTreeView,
  ];
}

/// Drives the source control panel for a single repository root.
///
/// The root tracks the active session cwd (see `RightToolsPanel`); mutating
/// operations refresh status on success and surface failures via
/// [GitState.errorMessage]. Runs git on the active storage backend (local,
/// WSL, or SSH).
class GitCubit extends Cubit<GitState> {
  GitCubit({required GitService service, HeadlessAiService? headless})
    : _service = service,
      _headless = headless ?? HeadlessAiService(),
      super(const GitState());

  final GitService _service;
  final HeadlessAiService _headless;

  /// Seeds [GitState.expandedFolderPaths] once after the first status load.
  bool _treeExpansionInitialized = false;

  /// Paths seen in the last status refresh. Used by [_reconcileSelectedPaths]
  /// to auto-check newly-appeared changes while preserving manual unchecks.
  Set<String> _knownChangedPaths = {};

  @visibleForTesting
  void debugSetState(GitState next) => _publish(next, recomputeRows: false);

  void _publish(GitState next, {bool recomputeRows = true}) {
    var published = next;
    if (recomputeRows) {
      published = next.copyWith(
        changesTreeView: visibleUnifiedGitChangesTreeView(
          staged: next.status.staged,
          unstaged: next.status.unstaged,
          expandedFolderPaths: next.expandedFolderPaths,
          selectedPaths: next.selectedPaths,
        ),
      );
    }
    if (published == state || isClosed) return;
    emit(published);
  }

  Future<void> setRepoRoot(String path) async {
    if (path == state.repoRoot) return;
    _treeExpansionInitialized = false;
    _branchesLoaded = false;
    _branchesInFlight = null;
    _knownChangedPaths = {};
    _publish(
      state.copyWith(
        repoRoot: path,
        branches: const [],
        expandedFolderPaths: const {},
        selectedPaths: const {},
        changesTreeView: const GitChangesTreeViewData(
          rows: [],
          stagedCount: 0,
          totalCount: 0,
        ),
        clearError: true,
      ),
      recomputeRows: false,
    );
    await refresh();
  }

  /// True while a `_runRefresh` chain is executing; a second [refresh] call sets
  /// [_refreshQueued] so exactly one trailing run catches up afterward.
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  /// Branch list is loaded lazily (see [ensureBranches]); reset per repo root.
  bool _branchesLoaded = false;

  /// Shared in-flight branch load, so concurrent [ensureBranches] calls (rapid
  /// picker opens / branch mutations) reuse one `git branch` instead of racing.
  Future<void>? _branchesInFlight;

  /// Refreshes git status, coalescing concurrent calls: at most one subprocess
  /// chain runs at a time, with a single trailing run if calls arrived while it
  /// was busy. On large repos `git status` can outlast the poll interval, so
  /// this prevents process pile-ups (mirrors orca's coalesced poll runner).
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
      if (_refreshQueued) {
        _refreshQueued = false;
        await refresh();
      }
    }
  }

  Future<void> _runRefresh() async {
    final dir = state.repoRoot;
    if (dir.isEmpty) {
      _publish(state.copyWith(status: GitRepoStatus.notARepository));
      return;
    }
    // Only flag loading on the very first fetch for this root; background polls
    // refresh in place so a warm panel never flashes a spinner.
    if (state.status == GitRepoStatus.notARepository &&
        !_treeExpansionInitialized) {
      _publish(state.copyWith(isLoading: true, clearError: true));
    } else if (state.errorMessage != null) {
      _publish(state.copyWith(clearError: true));
    }
    try {
      if (!await _service.isAvailable) {
        if (isClosed || state.repoRoot != dir) return;
        _publish(
          state.copyWith(
            gitAvailable: false,
            isLoading: false,
            status: GitRepoStatus.notARepository,
          ),
        );
        return;
      }
      final status = await _service.status(dir);
      if (isClosed || state.repoRoot != dir) return;
      var expanded = state.expandedFolderPaths;
      if (!_treeExpansionInitialized) {
        expanded = gitChangesDefaultExpandedFolders([
          ...status.staged,
          ...status.unstaged,
        ]);
        _treeExpansionInitialized = true;
      }
      final selected = _reconcileSelectedPaths(status);
      final next = state.copyWith(
        gitAvailable: true,
        isLoading: false,
        status: status,
        expandedFolderPaths: expanded,
        selectedPaths: selected,
      );
      if (next.status == state.status &&
          next.expandedFolderPaths == state.expandedFolderPaths &&
          next.selectedPaths == state.selectedPaths &&
          next.isLoading == state.isLoading &&
          next.gitAvailable == state.gitAvailable &&
          next.errorMessage == state.errorMessage) {
        return;
      }
      _publish(next);
    } on GitException catch (e) {
      if (isClosed || state.repoRoot != dir) return;
      _publish(state.copyWith(isLoading: false, errorMessage: e.message));
    }
  }

  /// Keeps manual selection across refreshes: drops paths that vanished,
  /// auto-checks newly-appeared changes, preserves everything else.
  Set<String> _reconcileSelectedPaths(GitRepoStatus status) {
    final changedNow = <String>{
      for (final c in status.staged) c.path,
      for (final c in status.unstaged) c.path,
    };
    final next = <String>{
      ...state.selectedPaths.where(changedNow.contains),
      ...changedNow.difference(_knownChangedPaths),
    };
    _knownChangedPaths = changedNow;
    return next;
  }

  /// Lazily loads the branch list for the current repo (first call only, unless
  /// [force]). Called when the branch picker opens — the header only needs
  /// [GitRepoStatus.branch], which already comes from `refresh`. Concurrent
  /// calls share one in-flight load.
  Future<void> ensureBranches({bool force = false}) {
    final dir = state.repoRoot;
    if (dir.isEmpty || !state.status.isRepository) {
      return Future<void>.value();
    }
    if (_branchesLoaded && !force) return Future<void>.value();
    return _branchesInFlight ??= _loadBranches(
      dir,
    ).whenComplete(() => _branchesInFlight = null);
  }

  Future<void> _loadBranches(String dir) async {
    try {
      final branches = await _service.branches(dir);
      if (isClosed || state.repoRoot != dir) return;
      _branchesLoaded = true;
      _publish(state.copyWith(branches: branches));
    } on GitException catch (e) {
      if (isClosed || state.repoRoot != dir) return;
      _publish(state.copyWith(errorMessage: e.message));
    }
  }

  void setCommitMessage(String message) {
    if (message == state.commitMessage) return;
    _publish(state.copyWith(commitMessage: message), recomputeRows: false);
  }

  void toggleFolderExpanded(String folderPath) {
    final next = Set<String>.from(state.expandedFolderPaths);
    if (next.contains(folderPath)) {
      next.remove(folderPath);
    } else {
      next.add(folderPath);
    }
    _publish(state.copyWith(expandedFolderPaths: next));
  }

  void expandAllFolders() {
    final all = gitChangesAllFolderPaths([
      ...state.status.staged,
      ...state.status.unstaged,
    ]);
    if (all.isEmpty) return;
    _publish(state.copyWith(expandedFolderPaths: all));
  }

  void collapseAllFolders() {
    _publish(state.copyWith(expandedFolderPaths: const {}));
  }

  void toggleExpandAllFolders() {
    if (state.allChangeFoldersExpanded) {
      collapseAllFolders();
    } else {
      expandAllFolders();
    }
  }

  /// Selection-model ops: these are pure UI state (no git), matching IDEA's
  /// "include in the next commit" checkboxes. Names are the legacy stage
  /// vocabulary; a later task renames them.
  Future<void> stage(GitFileChange change) async {
    _publish(
      state.copyWith(selectedPaths: {...state.selectedPaths, change.path}),
    );
  }

  Future<void> unstage(GitFileChange change) async {
    final next = {...state.selectedPaths}..remove(change.path);
    _publish(state.copyWith(selectedPaths: next));
  }

  Future<void> stageFolder(String folderPath) async {
    final changed = _changedPathsUnder(folderPath);
    _publish(state.copyWith(selectedPaths: {...state.selectedPaths, ...changed}));
  }

  Future<void> unstageFolder(String folderPath) async {
    final changed = _changedPathsUnder(folderPath);
    final next = {...state.selectedPaths}..removeAll(changed);
    _publish(state.copyWith(selectedPaths: next));
  }

  Future<void> stageAll() async {
    _publish(
      state.copyWith(
        selectedPaths: <String>{
          for (final c in [...state.status.staged, ...state.status.unstaged])
            c.path,
        },
      ),
    );
  }

  Future<void> unstageAll() async {
    _publish(state.copyWith(selectedPaths: const <String>{}));
  }

  Set<String> _changedPathsUnder(String folderPath) => <String>{
    for (final c in [...state.status.staged, ...state.status.unstaged])
      if (c.path == folderPath || c.path.startsWith('$folderPath/')) c.path,
  };

  Future<void> discard(GitFileChange change) =>
      _mutate(() => _service.discard(state.repoRoot, change));

  Future<void> discardAll() => _mutate(() => _service.discardAll(state.repoRoot));

  Future<void> discardFolder(String folderPath) =>
      _mutate(() => _service.discardFolder(state.repoRoot, folderPath));

  /// Commits the selected paths. No-op when the message is blank or nothing is
  /// selected.
  Future<bool> commit() async {
    final message = state.commitMessage.trim();
    final paths = state.selectedPaths.toList();
    if (message.isEmpty || paths.isEmpty) {
      return false;
    }
    final ok = await _mutate(
      () => _service.commitSelected(state.repoRoot, message, paths),
    );
    if (ok) {
      _publish(state.copyWith(commitMessage: ''), recomputeRows: false);
    }
    return ok;
  }

  Future<void> push() => _mutate(() => _service.push(state.repoRoot));

  Future<void> pull() => _mutate(() => _service.pull(state.repoRoot));

  Future<void> checkoutBranch(String name) async {
    if (await _mutate(() => _service.checkout(state.repoRoot, name))) {
      await ensureBranches(force: true);
    }
  }

  Future<void> createBranch(String name) async {
    if (await _mutate(
      () => _service.createBranch(state.repoRoot, name.trim()),
    )) {
      await ensureBranches(force: true);
    }
  }

  /// Generates a commit message draft from the staged diff via [setting].
  /// Fills [GitState.commitMessage]; never commits.
  Future<void> generateCommitMessage(AiFeatureSetting setting) async {
    final dir = state.repoRoot;
    if (dir.isEmpty ||
        state.status.staged.isEmpty ||
        state.generatingCommitMessage) {
      return;
    }
    _publish(state.copyWith(generatingCommitMessage: true, clearError: true));
    try {
      final diff = await _service.stagedDiff(dir);
      if (isClosed || state.repoRoot != dir) return;
      if (diff.trim().isEmpty) {
        _publish(
          state.copyWith(generatingCommitMessage: false),
          recomputeRows: false,
        );
        return;
      }
      final result = await _headless.run(
        setting: setting,
        prompt: buildCommitMessagePrompt(diff),
        workingDirectory: dir,
      );
      if (isClosed || state.repoRoot != dir) return;
      _publish(
        state.copyWith(
          commitMessage: cleanCommitMessageOutput(result.text),
          generatingCommitMessage: false,
        ),
        recomputeRows: false,
      );
    } on GitException catch (e) {
      if (isClosed) return;
      _publish(
        state.copyWith(generatingCommitMessage: false, errorMessage: e.message),
        recomputeRows: false,
      );
    } on HeadlessAiException catch (e) {
      if (isClosed) return;
      _publish(
        state.copyWith(generatingCommitMessage: false, errorMessage: e.message),
        recomputeRows: false,
      );
    } on Object catch (e) {
      if (isClosed) return;
      _publish(
        state.copyWith(
          generatingCommitMessage: false,
          errorMessage: e.toString(),
        ),
        recomputeRows: false,
      );
    }
  }

  Future<String?> diff(
    GitFileChange change, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    try {
      return await _service.diff(
        state.repoRoot,
        change,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      );
    } on GitException catch (e) {
      _publish(state.copyWith(errorMessage: e.message), recomputeRows: false);
      return null;
    }
  }

  /// Working tree vs HEAD for [relativePath]. When the path is untracked in
  /// the current status snapshot, uses `--no-index` like [diff] for untracked.
  Future<String?> diffAgainstHead(
    String relativePath, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    try {
      final untracked = state.status.unstaged.any(
        (c) => c.path == relativePath && c.kind == GitChangeKind.untracked,
      );
      return await _service.diffAgainstHead(
        state.repoRoot,
        relativePath,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
        untracked: untracked,
      );
    } on GitException catch (e) {
      _publish(state.copyWith(errorMessage: e.message), recomputeRows: false);
      return null;
    }
  }

  /// Runs [action], then refreshes. Returns false (and sets an error) on
  /// failure. Guards against re-entrancy via [GitState.busy].
  Future<bool> _mutate(Future<void> Function() action) async {
    if (state.busy) return false;
    _publish(
      state.copyWith(busy: true, clearError: true),
      recomputeRows: false,
    );
    try {
      await action();
      await refresh();
      if (isClosed) return false;
      _publish(state.copyWith(busy: false), recomputeRows: false);
      return true;
    } on GitException catch (e) {
      if (isClosed) return false;
      _publish(
        state.copyWith(busy: false, errorMessage: e.message),
        recomputeRows: false,
      );
      return false;
    }
  }
}
