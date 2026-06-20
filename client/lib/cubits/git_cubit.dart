import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ai_feature_setting.dart';
import '../models/git_status.dart';
import '../services/ai/commit_message_prompt.dart';
import '../services/ai/headless_ai_service.dart';
import '../services/git/git_changes_visible_rows.dart';
import '../services/git/git_service.dart';

export '../services/git/git_changes_visible_rows.dart' show GitChangesViewMode;

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
    this.changesViewMode = GitChangesViewMode.tree,
    this.expandedFolderPaths = const {},
    this.generatingCommitMessage = false,
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
  final GitChangesViewMode changesViewMode;
  final Set<String> expandedFolderPaths;
  final bool generatingCommitMessage;

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
    GitChangesViewMode? changesViewMode,
    Set<String>? expandedFolderPaths,
    bool? generatingCommitMessage,
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
      changesViewMode: changesViewMode ?? this.changesViewMode,
      expandedFolderPaths: expandedFolderPaths ?? this.expandedFolderPaths,
      generatingCommitMessage:
          generatingCommitMessage ?? this.generatingCommitMessage,
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
    changesViewMode,
    expandedFolderPaths,
    generatingCommitMessage,
  ];
}

/// Drives the source control panel for a single repository root.
///
/// The root tracks the active session cwd (see `RightToolsPanel`); mutating
/// operations refresh status on success and surface failures via
/// [GitState.errorMessage]. Desktop-local only.
class GitCubit extends Cubit<GitState> {
  GitCubit({GitService? service, HeadlessAiService? headless})
    : _service =
          service ?? GitService.debugOverrideFactory?.call() ?? GitService(),
      _headless = headless ?? HeadlessAiService(),
      super(const GitState());

  final GitService _service;
  final HeadlessAiService _headless;

  /// Seeds [GitState.expandedFolderPaths] once after the first status load in
  /// tree mode (matches [toggleChangesViewMode] when switching from list).
  bool _treeExpansionInitialized = false;

  @visibleForTesting
  void debugSetState(GitState next) => _emit(next);

  void _emit(GitState next) {
    if (!isClosed) emit(next);
  }

  Future<void> setRepoRoot(String path) async {
    if (path == state.repoRoot) return;
    _treeExpansionInitialized = false;
    _branchesLoaded = false;
    _branchesInFlight = null;
    // Clear the previous repo's branch list so a reused cubit never shows a
    // stale picker before the lazy reload lands.
    _emit(state.copyWith(repoRoot: path, branches: const [], clearError: true));
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
      _emit(state.copyWith(status: GitRepoStatus.notARepository));
      return;
    }
    // Only flag loading on the very first fetch for this root; background polls
    // refresh in place so a warm panel never flashes a spinner.
    if (state.status == GitRepoStatus.notARepository && !_treeExpansionInitialized) {
      _emit(state.copyWith(isLoading: true, clearError: true));
    } else {
      _emit(state.copyWith(clearError: true));
    }
    try {
      if (!await _service.isAvailable) {
        if (isClosed || state.repoRoot != dir) return;
        _emit(
          state.copyWith(
            gitAvailable: false,
            isLoading: false,
            status: GitRepoStatus.notARepository,
          ),
        );
        return;
      }
      // Status is the hot path; branches load lazily on demand (ensureBranches)
      // so the panel paints without waiting on a second subprocess.
      final status = await _service.status(dir);
      if (isClosed || state.repoRoot != dir) return;
      var expanded = state.expandedFolderPaths;
      if (state.changesViewMode == GitChangesViewMode.tree &&
          !_treeExpansionInitialized) {
        expanded = gitChangesDefaultExpandedFolders([
          ...status.staged,
          ...status.unstaged,
        ]);
        _treeExpansionInitialized = true;
      }
      _emit(
        state.copyWith(
          gitAvailable: true,
          isLoading: false,
          status: status,
          expandedFolderPaths: expanded,
        ),
      );
    } on GitException catch (e) {
      if (isClosed || state.repoRoot != dir) return;
      _emit(state.copyWith(isLoading: false, errorMessage: e.message));
    }
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
      _emit(state.copyWith(branches: branches));
    } on GitException catch (e) {
      if (isClosed || state.repoRoot != dir) return;
      _emit(state.copyWith(errorMessage: e.message));
    }
  }

  void setCommitMessage(String message) {
    _emit(state.copyWith(commitMessage: message));
  }

  void toggleChangesViewMode() {
    final next = state.changesViewMode == GitChangesViewMode.list
        ? GitChangesViewMode.tree
        : GitChangesViewMode.list;
    var expanded = state.expandedFolderPaths;
    if (next == GitChangesViewMode.tree && expanded.isEmpty) {
      expanded = gitChangesDefaultExpandedFolders([
        ...state.status.staged,
        ...state.status.unstaged,
      ]);
    }
    _emit(state.copyWith(changesViewMode: next, expandedFolderPaths: expanded));
  }

  void toggleFolderExpanded(String folderPath) {
    final next = Set<String>.from(state.expandedFolderPaths);
    if (next.contains(folderPath)) {
      next.remove(folderPath);
    } else {
      next.add(folderPath);
    }
    _emit(state.copyWith(expandedFolderPaths: next));
  }

  void expandAllFolders() {
    final all = gitChangesAllFolderPaths([
      ...state.status.staged,
      ...state.status.unstaged,
    ]);
    if (all.isEmpty) return;
    _emit(state.copyWith(expandedFolderPaths: all));
  }

  void collapseAllFolders() {
    _emit(state.copyWith(expandedFolderPaths: const {}));
  }

  void toggleExpandAllFolders() {
    if (state.allChangeFoldersExpanded) {
      collapseAllFolders();
    } else {
      expandAllFolders();
    }
  }

  Future<void> stage(GitFileChange change) =>
      _mutate(() => _service.stage(state.repoRoot, [change.path]));

  Future<void> unstage(GitFileChange change) =>
      _mutate(() => _service.unstage(state.repoRoot, [change.path]));

  Future<void> stageFolder(String folderPath) =>
      _mutate(() => _service.stage(state.repoRoot, [folderPath]));

  Future<void> unstageFolder(String folderPath) =>
      _mutate(() => _service.unstage(state.repoRoot, [folderPath]));

  Future<void> stageAll() => _mutate(() => _service.stageAll(state.repoRoot));

  Future<void> unstageAll() =>
      _mutate(() => _service.unstageAll(state.repoRoot));

  Future<void> discard(GitFileChange change) =>
      _mutate(() => _service.discard(state.repoRoot, change));

  /// Commits staged changes. No-op (with an error message) when the message is
  /// blank or nothing is staged.
  Future<bool> commit() async {
    final message = state.commitMessage.trim();
    if (message.isEmpty || state.status.staged.isEmpty) {
      return false;
    }
    final ok = await _mutate(() => _service.commit(state.repoRoot, message));
    if (ok) {
      _emit(state.copyWith(commitMessage: ''));
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
    if (await _mutate(() => _service.createBranch(state.repoRoot, name.trim()))) {
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
    _emit(state.copyWith(generatingCommitMessage: true, clearError: true));
    try {
      final diff = await _service.stagedDiff(dir);
      if (isClosed || state.repoRoot != dir) return;
      if (diff.trim().isEmpty) {
        _emit(state.copyWith(generatingCommitMessage: false));
        return;
      }
      final result = await _headless.run(
        setting: setting,
        prompt: buildCommitMessagePrompt(diff),
        workingDirectory: dir,
      );
      if (isClosed || state.repoRoot != dir) return;
      _emit(
        state.copyWith(
          commitMessage: cleanCommitMessageOutput(result.text),
          generatingCommitMessage: false,
        ),
      );
    } on GitException catch (e) {
      if (isClosed) return;
      _emit(state.copyWith(generatingCommitMessage: false, errorMessage: e.message));
    } on HeadlessAiException catch (e) {
      if (isClosed) return;
      _emit(state.copyWith(generatingCommitMessage: false, errorMessage: e.message));
    } on Object catch (e) {
      if (isClosed) return;
      // Never strand the spinner on an unexpected failure.
      _emit(
        state.copyWith(
          generatingCommitMessage: false,
          errorMessage: e.toString(),
        ),
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
      _emit(state.copyWith(errorMessage: e.message));
      return null;
    }
  }

  /// Runs [action], then refreshes. Returns false (and sets an error) on
  /// failure. Guards against re-entrancy via [GitState.busy].
  Future<bool> _mutate(Future<void> Function() action) async {
    if (state.busy) return false;
    _emit(state.copyWith(busy: true, clearError: true));
    try {
      await action();
      await refresh();
      if (isClosed) return false;
      _emit(state.copyWith(busy: false));
      return true;
    } on GitException catch (e) {
      if (isClosed) return false;
      _emit(state.copyWith(busy: false, errorMessage: e.message));
      return false;
    }
  }
}
