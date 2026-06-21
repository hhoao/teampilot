import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/git_worktree.dart';
import '../services/git/git_worktree_service.dart';
import '../utils/workspace_path_utils.dart';

/// Narrow seam so tests inject a fake without a real GitWorktreeService.
abstract class WorktreeLister {
  Future<List<GitWorktree>> list(String repoPath);
}

class _ServiceLister implements WorktreeLister {
  _ServiceLister(this._svc);
  final GitWorktreeService _svc;
  @override
  Future<List<GitWorktree>> list(String repoPath) => _svc.list(repoPath);
}

class WorktreeState {
  const WorktreeState({
    this.repoPath = '',
    this.worktrees = const [],
    this.currentWorktreePath = '',
    this.collapsed = const {},
    this.loading = false,
  });

  final String repoPath;
  final List<GitWorktree> worktrees;
  final String currentWorktreePath;
  final Set<String> collapsed;
  final bool loading;

  /// True once there is more than the main worktree (drives grouped vs flat).
  bool get hasMultipleWorktrees => worktrees.length > 1;

  WorktreeState copyWith({
    String? repoPath,
    List<GitWorktree>? worktrees,
    String? currentWorktreePath,
    Set<String>? collapsed,
    bool? loading,
  }) =>
      WorktreeState(
        repoPath: repoPath ?? this.repoPath,
        worktrees: worktrees ?? this.worktrees,
        currentWorktreePath: currentWorktreePath ?? this.currentWorktreePath,
        collapsed: collapsed ?? this.collapsed,
        loading: loading ?? this.loading,
      );
}

class WorktreeCubit extends Cubit<WorktreeState> {
  WorktreeCubit({WorktreeLister? lister, GitWorktreeService? service})
      : _lister = lister ??
            _ServiceLister(service ??
                GitWorktreeService.debugOverrideFactory?.call() ??
                GitWorktreeService()),
        super(const WorktreeState());

  final WorktreeLister _lister;

  Future<void> load(String repoPath) async {
    emit(state.copyWith(repoPath: repoPath, loading: true));
    final list = await _lister.list(repoPath);
    final current =
        list.any((w) => workspacePathsEqual(w.path, state.currentWorktreePath))
            ? state.currentWorktreePath
            : (list.isNotEmpty ? list.first.path : repoPath);
    emit(state.copyWith(
      worktrees: list,
      currentWorktreePath: current,
      loading: false,
    ));
  }

  void setCurrentWorktree(String path) =>
      emit(state.copyWith(currentWorktreePath: normalizeWorkspacePath(path)));

  void toggleCollapsed(String path) {
    final next = {...state.collapsed};
    next.contains(path) ? next.remove(path) : next.add(path);
    emit(state.copyWith(collapsed: next));
  }
}
