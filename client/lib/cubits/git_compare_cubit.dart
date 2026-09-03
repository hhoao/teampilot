import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/git_compare.dart';
import '../models/git_status.dart';
import '../services/git/git_changes_visible_rows.dart';
import '../services/git/git_history_service.dart';
import '../services/git/git_service.dart' show GitException;

class GitCompareState extends Equatable {
  const GitCompareState({
    required this.spec,
    this.files = const [],
    this.loading = false,
    this.error,
    this.expandedFolderPaths = const {},
    this.selectedPath,
  });

  final GitCompareSpec spec;
  final List<GitFileChange> files;
  final bool loading;
  final String? error;
  final Set<String> expandedFolderPaths;
  final String? selectedPath;

  static const Object _unset = Object();

  GitCompareState copyWith({
    GitCompareSpec? spec,
    List<GitFileChange>? files,
    bool? loading,
    Object? error = _unset,
    Set<String>? expandedFolderPaths,
    Object? selectedPath = _unset,
  }) {
    return GitCompareState(
      spec: spec ?? this.spec,
      files: files ?? this.files,
      loading: loading ?? this.loading,
      error: identical(error, _unset) ? this.error : error as String?,
      expandedFolderPaths: expandedFolderPaths ?? this.expandedFolderPaths,
      selectedPath: identical(selectedPath, _unset)
          ? this.selectedPath
          : selectedPath as String?,
    );
  }

  @override
  List<Object?> get props => [
    spec,
    files,
    loading,
    error,
    expandedFolderPaths,
    selectedPath,
  ];
}

class GitCompareCubit extends Cubit<GitCompareState> {
  GitCompareCubit({
    required GitCompareSpec spec,
    required GitHistoryService history,
  }) : _history = history,
       super(GitCompareState(spec: spec));

  final GitHistoryService _history;
  int _loadGen = 0;

  Future<void> load() async {
    final gen = ++_loadGen;
    emit(state.copyWith(loading: true, error: null));
    try {
      final files = await _history.listDiffFiles(
        state.spec.repoRoot,
        state.spec.left,
        state.spec.right,
      );
      if (gen != _loadGen || isClosed) return;
      final expanded = state.expandedFolderPaths.isEmpty
          ? gitChangesDefaultExpandedFolders(files)
          : state.expandedFolderPaths;
      emit(
        state.copyWith(
          files: files,
          loading: false,
          error: null,
          expandedFolderPaths: expanded,
        ),
      );
    } on GitException catch (e) {
      if (gen != _loadGen || isClosed) return;
      emit(state.copyWith(loading: false, error: e.message));
    }
  }

  Future<void> refresh() => load();

  void toggleFolder(String folderPath) {
    final next = Set<String>.from(state.expandedFolderPaths);
    if (!next.add(folderPath)) next.remove(folderPath);
    emit(state.copyWith(expandedFolderPaths: next));
  }

  void selectPath(String? path) {
    emit(state.copyWith(selectedPath: path));
  }

  Future<String?> diffFor(
    String relativePath, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
  }) async {
    final untracked = state.files.any(
      (f) => f.path == relativePath && f.kind == GitChangeKind.untracked,
    );
    try {
      return await _history.fileDiff(
        state.spec.repoRoot,
        state.spec.left,
        state.spec.right,
        relativePath,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
        untracked: untracked,
      );
    } on GitException {
      return null;
    }
  }
}
