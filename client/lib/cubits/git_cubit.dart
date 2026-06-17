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
    _emit(state.copyWith(repoRoot: path, clearError: true));
    await refresh();
  }

  Future<void> refresh() async {
    final dir = state.repoRoot;
    if (dir.isEmpty) {
      _emit(state.copyWith(status: GitRepoStatus.notARepository));
      return;
    }
    _emit(state.copyWith(isLoading: true, clearError: true));
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
      final status = await _service.status(dir);
      if (isClosed || state.repoRoot != dir) return;
      final branches = status.isRepository
          ? await _service.branches(dir)
          : const <String>[];
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
          branches: branches,
          expandedFolderPaths: expanded,
        ),
      );
    } on GitException catch (e) {
      if (isClosed || state.repoRoot != dir) return;
      _emit(state.copyWith(isLoading: false, errorMessage: e.message));
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

  Future<void> stage(GitFileChange change) =>
      _mutate(() => _service.stage(state.repoRoot, [change.path]));

  Future<void> unstage(GitFileChange change) =>
      _mutate(() => _service.unstage(state.repoRoot, [change.path]));

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

  Future<void> checkoutBranch(String name) =>
      _mutate(() => _service.checkout(state.repoRoot, name));

  Future<void> createBranch(String name) =>
      _mutate(() => _service.createBranch(state.repoRoot, name.trim()));

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
