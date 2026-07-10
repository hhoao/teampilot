import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/editor/editor_messages.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import 'workbench/workbench_tab.dart';

class DiffTabState extends Equatable {
  const DiffTabState({
    required this.absolutePath,
    required this.staged,
    required this.title,
    required this.diffText,
  });

  final String absolutePath;
  final bool staged;
  final String title;
  final String diffText;

  String get key =>
      WorkbenchTabId.diffKey(absolutePath, staged: staged);

  DiffTabState copyWith({String? diffText, String? title}) {
    return DiffTabState(
      absolutePath: absolutePath,
      staged: staged,
      title: title ?? this.title,
      diffText: diffText ?? this.diffText,
    );
  }

  @override
  List<Object?> get props => [absolutePath, staged, title, diffText];
}

class WorkspaceEditorBucket extends Equatable {
  const WorkspaceEditorBucket({
    this.openFilePaths = const [],
    this.openDiffs = const {},
    this.dirtyPaths = const {},
    this.loadingPaths = const {},
    this.errorByPath = const {},
    this.readOnlyPaths = const {},
  });

  final List<String> openFilePaths;
  final Map<String, DiffTabState> openDiffs;
  final Set<String> dirtyPaths;
  final Set<String> loadingPaths;
  final Map<String, String> errorByPath;
  final Set<String> readOnlyPaths;

  bool get hasOpenFiles => openFilePaths.isNotEmpty;
  bool get hasOpenDiffs => openDiffs.isNotEmpty;

  bool isDirty(String path) => dirtyPaths.contains(path);

  WorkspaceEditorBucket copyWith({
    List<String>? openFilePaths,
    Map<String, DiffTabState>? openDiffs,
    Set<String>? dirtyPaths,
    Set<String>? loadingPaths,
    Map<String, String>? errorByPath,
    Set<String>? readOnlyPaths,
  }) {
    return WorkspaceEditorBucket(
      openFilePaths: openFilePaths ?? this.openFilePaths,
      openDiffs: openDiffs ?? this.openDiffs,
      dirtyPaths: dirtyPaths ?? this.dirtyPaths,
      loadingPaths: loadingPaths ?? this.loadingPaths,
      errorByPath: errorByPath ?? this.errorByPath,
      readOnlyPaths: readOnlyPaths ?? this.readOnlyPaths,
    );
  }

  @override
  List<Object?> get props => [
    openFilePaths,
    openDiffs,
    dirtyPaths,
    loadingPaths,
    errorByPath,
    readOnlyPaths,
  ];
}

class EditorState extends Equatable {
  const EditorState({
    this.byWorkspace = const {},
    this.snackbarMessage,
  });

  final Map<String, WorkspaceEditorBucket> byWorkspace;
  final String? snackbarMessage;

  WorkspaceEditorBucket bucket(String workspaceId) =>
      byWorkspace[workspaceId] ?? const WorkspaceEditorBucket();

  bool get hasAnyOpenFiles =>
      byWorkspace.values.any((b) => b.hasOpenFiles);

  String fileNameFor(String path) => p.basename(path);

  EditorState withBucket(String workspaceId, WorkspaceEditorBucket bucket) {
    return EditorState(
      byWorkspace: {...byWorkspace, workspaceId: bucket},
      snackbarMessage: snackbarMessage,
    );
  }

  EditorState copyWith({
    Map<String, WorkspaceEditorBucket>? byWorkspace,
    String? snackbarMessage,
    bool clearSnackbar = false,
  }) {
    return EditorState(
      byWorkspace: byWorkspace ?? this.byWorkspace,
      snackbarMessage: clearSnackbar
          ? null
          : (snackbarMessage ?? this.snackbarMessage),
    );
  }

  @override
  List<Object?> get props => [byWorkspace, snackbarMessage];
}

class _OpenFileHandle {
  _OpenFileHandle({required this.controller, required this.onDirty});

  final CodeLineEditingController controller;
  final VoidCallback onDirty;
  String? savedText;
  VoidCallback? _listener;

  /// Stable per-file identity for the [CodeEditor] element.
  final GlobalKey editorKey = GlobalKey(debugLabel: 'file-editor');

  void attachListener() {
    _listener ??= () {
      if (savedText != null && controller.text != savedText) {
        onDirty();
      }
    };
    controller.addListener(_listener!);
  }

  void dispose() {
    if (_listener != null) {
      controller.removeListener(_listener!);
    }
    controller.dispose();
  }
}

typedef DiffReload =
    Future<String?> Function(bool ignoreWhitespace, bool fullContext);

class EditorCubit extends Cubit<EditorState> {
  EditorCubit({Filesystem? fs})
    : _fs = fs ?? AppStorage.fs,
      super(const EditorState());

  final Filesystem _fs;
  final Map<String, Filesystem> _fsByHandle = {};
  final Map<String, _OpenFileHandle> _handles = {};
  final Map<String, DiffReload> _diffReloadByKey = {};

  String _handleKey(String workspaceId, String path) => '$workspaceId\x00$path';

  CodeLineEditingController? controllerFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.controller;

  GlobalKey? editorKeyFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.editorKey;

  bool isReadOnly(String workspaceId, String path) =>
      state.bucket(workspaceId).readOnlyPaths.contains(path);

  DiffReload? diffReloadFor(String diffKey) => _diffReloadByKey[diffKey];

  void clearSnackbarMessage() {
    if (state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbar: true));
  }

  Future<void> openFile(
    String workspaceId,
    String path, {
    Filesystem? fs,
  }) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;

    final bucket = state.bucket(workspaceId);
    if (bucket.openFilePaths.contains(normalized)) {
      return;
    }

    if (!isEditorOpenableFilePath(normalized)) {
      emit(state.copyWith(snackbarMessage: EditorMessage.binaryFile));
      return;
    }

    final filesystem = fs ?? _fs;
    final loading = Set<String>.from(bucket.loadingPaths)..add(normalized);
    emit(
      state
          .withBucket(workspaceId, bucket.copyWith(loadingPaths: loading))
          .copyWith(clearSnackbar: true),
    );

    try {
      final stat = await filesystem.stat(normalized);
      if (!_stillLoading(workspaceId, normalized)) return;
      if (!stat.exists || !stat.isFile) {
        emit(_clearLoading(workspaceId, normalized, error: EditorMessage.fileNotFound));
        return;
      }
      final size = stat.size ?? 0;
      if (size > kEditorMaxFileBytes) {
        emit(_clearLoading(workspaceId, normalized, error: EditorMessage.fileTooLarge));
        return;
      }

      final content = await filesystem.readString(normalized);
      if (!_stillLoading(workspaceId, normalized)) return;
      if (content == null) {
        emit(_clearLoading(workspaceId, normalized, error: EditorMessage.couldNotRead));
        return;
      }

      final key = _handleKey(workspaceId, normalized);
      final controller = CodeLineEditingController.fromText(content);
      final handle = _OpenFileHandle(
        controller: controller,
        onDirty: () => _markDirty(workspaceId, normalized),
      )..savedText = content;
      handle.attachListener();
      _handles[key] = handle;
      _fsByHandle[key] = filesystem;

      final current = state.bucket(workspaceId);
      final paths = [...current.openFilePaths, normalized];
      final errors = Map<String, String>.from(current.errorByPath)
        ..remove(normalized);
      final loadingDone = Set<String>.from(current.loadingPaths)
        ..remove(normalized);

      emit(
        state
            .withBucket(
              workspaceId,
              current.copyWith(
                openFilePaths: paths,
                loadingPaths: loadingDone,
                errorByPath: errors,
              ),
            )
            .copyWith(clearSnackbar: true),
      );
    } on Object catch (e) {
      if (!_stillLoading(workspaceId, normalized)) return;
      emit(_clearLoading(workspaceId, normalized, error: e.toString()));
    }
  }

  bool _stillLoading(String workspaceId, String path) =>
      state.bucket(workspaceId).loadingPaths.contains(path);

  void openDiff({
    required String workspaceId,
    required String absolutePath,
    required bool staged,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
  }) {
    final key = WorkbenchTabId.diffKey(absolutePath, staged: staged);
    final bucket = state.bucket(workspaceId);
    final tab = DiffTabState(
      absolutePath: absolutePath,
      staged: staged,
      title: title,
      diffText: diffText,
    );
    if (reloadDiff != null) {
      _diffReloadByKey[key] = reloadDiff;
    }
    final diffs = Map<String, DiffTabState>.from(bucket.openDiffs)..[key] = tab;
    emit(state.withBucket(workspaceId, bucket.copyWith(openDiffs: diffs)));
  }

  void updateDiffText(String workspaceId, String diffKey, String diffText) {
    final bucket = state.bucket(workspaceId);
    final existing = bucket.openDiffs[diffKey];
    if (existing == null) return;
    final diffs = Map<String, DiffTabState>.from(bucket.openDiffs)
      ..[diffKey] = existing.copyWith(diffText: diffText);
    emit(state.withBucket(workspaceId, bucket.copyWith(openDiffs: diffs)));
  }

  void closeDiff(String workspaceId, String diffKey) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.openDiffs.containsKey(diffKey)) return;
    _diffReloadByKey.remove(diffKey);
    final diffs = Map<String, DiffTabState>.from(bucket.openDiffs)
      ..remove(diffKey);
    emit(state.withBucket(workspaceId, bucket.copyWith(openDiffs: diffs)));
  }

  EditorState _clearLoading(
    String workspaceId,
    String path, {
    String? error,
  }) {
    final bucket = state.bucket(workspaceId);
    final loadingDone = Set<String>.from(bucket.loadingPaths)..remove(path);
    if (error == null) {
      return state.withBucket(
        workspaceId,
        bucket.copyWith(loadingPaths: loadingDone),
      );
    }
    final errors = Map<String, String>.from(bucket.errorByPath)..[path] = error;
    return state
        .withBucket(
          workspaceId,
          bucket.copyWith(loadingPaths: loadingDone, errorByPath: errors),
        )
        .copyWith(snackbarMessage: error);
  }

  void _markDirty(String workspaceId, String path) {
    final bucket = state.bucket(workspaceId);
    if (bucket.dirtyPaths.contains(path)) return;
    final dirty = Set<String>.from(bucket.dirtyPaths)..add(path);
    emit(state.withBucket(workspaceId, bucket.copyWith(dirtyPaths: dirty)));
  }

  /// Returns `false` when the tab is dirty and [force] is false.
  bool closeFile(
    String workspaceId,
    String path, {
    bool force = false,
  }) {
    final bucket = state.bucket(workspaceId);
    final wasOpen = bucket.openFilePaths.contains(path);
    final wasLoading = bucket.loadingPaths.contains(path);
    if (!wasOpen && !wasLoading) return true;
    if (wasOpen && !force && bucket.dirtyPaths.contains(path)) {
      return false;
    }
    _disposeHandle(workspaceId, path);

    final paths = List<String>.from(bucket.openFilePaths)..remove(path);
    final dirty = Set<String>.from(bucket.dirtyPaths)..remove(path);
    final errors = Map<String, String>.from(bucket.errorByPath)..remove(path);
    final readOnly = Set<String>.from(bucket.readOnlyPaths)..remove(path);
    final loading = Set<String>.from(bucket.loadingPaths)..remove(path);

    emit(
      state.withBucket(
        workspaceId,
        bucket.copyWith(
          openFilePaths: paths,
          dirtyPaths: dirty,
          errorByPath: errors,
          readOnlyPaths: readOnly,
          loadingPaths: loading,
        ),
      ),
    );
    return true;
  }

  void revertFile(String workspaceId, String path) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.dirtyPaths.contains(path)) return;
    final handle = _handles[_handleKey(workspaceId, path)];
    final saved = handle?.savedText;
    if (handle == null || saved == null) return;
    handle.controller.text = saved;
    final dirty = Set<String>.from(bucket.dirtyPaths)..remove(path);
    emit(state.withBucket(workspaceId, bucket.copyWith(dirtyPaths: dirty)));
  }

  Future<bool> saveFile(String workspaceId, String path) async {
    final handle = _handles[_handleKey(workspaceId, path)];
    if (handle == null) return false;
    if (state.bucket(workspaceId).readOnlyPaths.contains(path)) {
      emit(state.copyWith(snackbarMessage: EditorMessage.readOnly));
      return false;
    }
    final fs = _fsByHandle[_handleKey(workspaceId, path)] ?? _fs;
    try {
      await fs.atomicWrite(path, handle.controller.text);
      handle.savedText = handle.controller.text;
      final bucket = state.bucket(workspaceId);
      final dirty = Set<String>.from(bucket.dirtyPaths)..remove(path);
      emit(
        state
            .withBucket(workspaceId, bucket.copyWith(dirtyPaths: dirty))
            .copyWith(clearSnackbar: true),
      );
      return true;
    } on Object catch (e) {
      emit(state.copyWith(snackbarMessage: EditorMessage.saveFailed(e)));
      return false;
    }
  }

  void _disposeHandle(String workspaceId, String path) {
    final key = _handleKey(workspaceId, path);
    _fsByHandle.remove(key);
    _handles.remove(key)?.dispose();
  }

  @override
  Future<void> close() async {
    for (final key in _handles.keys.toList()) {
      _handles.remove(key)?.dispose();
    }
    _fsByHandle.clear();
    _diffReloadByKey.clear();
    return super.close();
  }
}
