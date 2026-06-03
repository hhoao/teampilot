import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/git_status.dart';
import '../services/git/git_service.dart';

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
  ];
}

/// Drives the source control panel for a single repository root.
///
/// The root tracks the active session cwd (see `RightToolsPanel`); mutating
/// operations refresh status on success and surface failures via
/// [GitState.errorMessage]. Desktop-local only.
class GitCubit extends Cubit<GitState> {
  GitCubit({GitService? service})
    : _service =
          service ?? GitService.debugOverrideFactory?.call() ?? GitService(),
      super(const GitState());

  final GitService _service;

  Future<void> setRepoRoot(String path) async {
    if (path == state.repoRoot) return;
    emit(state.copyWith(repoRoot: path, clearError: true));
    await refresh();
  }

  Future<void> refresh() async {
    final dir = state.repoRoot;
    if (dir.isEmpty) {
      emit(state.copyWith(status: GitRepoStatus.notARepository));
      return;
    }
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      if (!await _service.isAvailable) {
        emit(
          state.copyWith(
            gitAvailable: false,
            isLoading: false,
            status: GitRepoStatus.notARepository,
          ),
        );
        return;
      }
      final status = await _service.status(dir);
      final branches = status.isRepository
          ? await _service.branches(dir)
          : const <String>[];
      emit(
        state.copyWith(
          gitAvailable: true,
          isLoading: false,
          status: status,
          branches: branches,
        ),
      );
    } on GitException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.message));
    }
  }

  void setCommitMessage(String message) {
    emit(state.copyWith(commitMessage: message));
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
      emit(state.copyWith(commitMessage: ''));
    }
    return ok;
  }

  Future<void> push() => _mutate(() => _service.push(state.repoRoot));

  Future<void> pull() => _mutate(() => _service.pull(state.repoRoot));

  Future<void> checkoutBranch(String name) =>
      _mutate(() => _service.checkout(state.repoRoot, name));

  Future<void> createBranch(String name) =>
      _mutate(() => _service.createBranch(state.repoRoot, name.trim()));

  Future<String?> diff(GitFileChange change) async {
    try {
      return await _service.diff(state.repoRoot, change);
    } on GitException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
      return null;
    }
  }

  /// Runs [action], then refreshes. Returns false (and sets an error) on
  /// failure. Guards against re-entrancy via [GitState.busy].
  Future<bool> _mutate(Future<void> Function() action) async {
    if (state.busy) return false;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await action();
      await refresh();
      emit(state.copyWith(busy: false));
      return true;
    } on GitException catch (e) {
      emit(state.copyWith(busy: false, errorMessage: e.message));
      return false;
    }
  }
}
