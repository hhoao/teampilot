import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/editor/editor_messages.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';

class EditorState extends Equatable {
  const EditorState({
    this.openPaths = const [],
    this.activeIndex = -1,
    this.dirtyPaths = const {},
    this.loadingPaths = const {},
    this.errorByPath = const {},
    this.readOnlyPaths = const {},
    this.snackbarMessage,
  });

  final List<String> openPaths;
  final int activeIndex;
  final Set<String> dirtyPaths;
  final Set<String> loadingPaths;
  final Map<String, String> errorByPath;
  final Set<String> readOnlyPaths;
  final String? snackbarMessage;

  bool get hasOpenFiles => openPaths.isNotEmpty;

  String? get activePath {
    if (activeIndex < 0 || activeIndex >= openPaths.length) return null;
    return openPaths[activeIndex];
  }

  bool isDirty(String path) => dirtyPaths.contains(path);

  String fileNameFor(String path) => p.basename(path);

  EditorState copyWith({
    List<String>? openPaths,
    int? activeIndex,
    Set<String>? dirtyPaths,
    Set<String>? loadingPaths,
    Map<String, String>? errorByPath,
    Set<String>? readOnlyPaths,
    String? snackbarMessage,
    bool clearSnackbar = false,
  }) {
    return EditorState(
      openPaths: openPaths ?? this.openPaths,
      activeIndex: activeIndex ?? this.activeIndex,
      dirtyPaths: dirtyPaths ?? this.dirtyPaths,
      loadingPaths: loadingPaths ?? this.loadingPaths,
      errorByPath: errorByPath ?? this.errorByPath,
      readOnlyPaths: readOnlyPaths ?? this.readOnlyPaths,
      snackbarMessage: clearSnackbar
          ? null
          : (snackbarMessage ?? this.snackbarMessage),
    );
  }

  @override
  List<Object?> get props => [
    openPaths,
    activeIndex,
    dirtyPaths,
    loadingPaths,
    errorByPath,
    readOnlyPaths,
    snackbarMessage,
  ];
}

class _OpenFileHandle {
  _OpenFileHandle({
    required this.controller,
    required this.onDirty,
  });

  final CodeLineEditingController controller;
  final VoidCallback onDirty;
  String? savedText;
  VoidCallback? _listener;

  /// Stable per-file identity for the [CodeEditor] element. A [GlobalKey] keeps
  /// Flutter from disposing and re-inflating the editor when the host subtree
  /// rebuilds, so this file's controller is never bound to two editors in one
  /// frame — re_editor otherwise notifies the deactivated editor's listener
  /// during the new editor's `initState` (`setState() called during build`).
  /// The editor is hosted once (see `WorkspaceFloatingEditor`), never inside a
  /// per-tab workbench, so this key is never present in two tabs at once.
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

class EditorCubit extends Cubit<EditorState> {
  EditorCubit({Filesystem? fs}) : _fs = fs ?? AppStorage.fs, super(const EditorState());

  final Filesystem _fs;
  final Map<String, _OpenFileHandle> _handles = {};

  CodeLineEditingController? controllerFor(String path) =>
      _handles[path]?.controller;

  /// Stable [GlobalKey] for the file's editor element; see [_OpenFileHandle].
  GlobalKey? editorKeyFor(String path) => _handles[path]?.editorKey;

  bool isReadOnly(String path) => state.readOnlyPaths.contains(path);

  void clearSnackbarMessage() {
    if (state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbar: true));
  }

  Future<void> openFile(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return;

    final existing = state.openPaths.indexOf(normalized);
    if (existing >= 0) {
      emit(state.copyWith(activeIndex: existing));
      return;
    }

    if (!isEditorOpenableFilePath(normalized)) {
      emit(
        state.copyWith(
          snackbarMessage: EditorMessage.binaryFile,
        ),
      );
      return;
    }

    final loading = Set<String>.from(state.loadingPaths)..add(normalized);
    emit(state.copyWith(loadingPaths: loading, clearSnackbar: true));

    try {
      final stat = await _fs.stat(normalized);
      if (!stat.exists || !stat.isFile) {
        emit(_clearLoading(normalized, error: EditorMessage.fileNotFound));
        return;
      }
      final size = stat.size ?? 0;
      if (size > kEditorMaxFileBytes) {
        emit(
          _clearLoading(
            normalized,
            error: EditorMessage.fileTooLarge,
          ),
        );
        return;
      }

      final content = await _fs.readString(normalized);
      if (content == null) {
        emit(_clearLoading(normalized, error: EditorMessage.couldNotRead));
        return;
      }

      final controller = CodeLineEditingController.fromText(content);
      final handle = _OpenFileHandle(
        controller: controller,
        onDirty: () => _markDirty(normalized),
      )..savedText = content;
      handle.attachListener();
      _handles[normalized] = handle;

      final paths = [...state.openPaths, normalized];
      final errors = Map<String, String>.from(state.errorByPath)
        ..remove(normalized);
      final loadingDone = Set<String>.from(state.loadingPaths)
        ..remove(normalized);

      emit(
        state.copyWith(
          openPaths: paths,
          activeIndex: paths.length - 1,
          loadingPaths: loadingDone,
          errorByPath: errors,
          clearSnackbar: true,
        ),
      );
    } on Object catch (e) {
      emit(_clearLoading(normalized, error: e.toString()));
    }
  }

  EditorState _clearLoading(String path, {String? error}) {
    final loadingDone = Set<String>.from(state.loadingPaths)..remove(path);
    if (error == null) {
      return state.copyWith(loadingPaths: loadingDone);
    }
    final errors = Map<String, String>.from(state.errorByPath)..[path] = error;
    return state.copyWith(
      loadingPaths: loadingDone,
      errorByPath: errors,
      snackbarMessage: error,
    );
  }

  void _markDirty(String path) {
    if (state.dirtyPaths.contains(path)) return;
    final dirty = Set<String>.from(state.dirtyPaths)..add(path);
    emit(state.copyWith(dirtyPaths: dirty));
  }

  void selectFile(int index) {
    if (index < 0 || index >= state.openPaths.length) return;
    if (index == state.activeIndex) return;
    emit(state.copyWith(activeIndex: index));
  }

  /// Returns `false` when the tab is dirty and [force] is false.
  bool closeFile(int index, {bool force = false}) {
    if (index < 0 || index >= state.openPaths.length) return true;
    final path = state.openPaths[index];
    if (!force && state.dirtyPaths.contains(path)) {
      return false;
    }
    _disposeHandle(path);

    final paths = List<String>.from(state.openPaths)..removeAt(index);
    var nextIndex = state.activeIndex;
    if (paths.isEmpty) {
      nextIndex = -1;
    } else if (index < state.activeIndex) {
      nextIndex = state.activeIndex - 1;
    } else if (index == state.activeIndex) {
      nextIndex = index.clamp(0, paths.length - 1);
      if (index >= paths.length) nextIndex = paths.length - 1;
    }

    final dirty = Set<String>.from(state.dirtyPaths)..remove(path);
    final errors = Map<String, String>.from(state.errorByPath)..remove(path);
    final readOnly = Set<String>.from(state.readOnlyPaths)..remove(path);
    final loading = Set<String>.from(state.loadingPaths)..remove(path);

    emit(
      state.copyWith(
        openPaths: paths,
        activeIndex: nextIndex,
        dirtyPaths: dirty,
        errorByPath: errors,
        readOnlyPaths: readOnly,
        loadingPaths: loading,
      ),
    );
    return true;
  }

  Future<bool> saveActive() async {
    final path = state.activePath;
    if (path == null) return false;
    return saveFile(path);
  }

  /// Discards unsaved edits and restores the last loaded/saved buffer.
  void revertActive() {
    final path = state.activePath;
    if (path == null || !state.dirtyPaths.contains(path)) return;
    final handle = _handles[path];
    final saved = handle?.savedText;
    if (handle == null || saved == null) return;
    handle.controller.text = saved;
    if (state.dirtyPaths.contains(path)) {
      final dirty = Set<String>.from(state.dirtyPaths)..remove(path);
      emit(state.copyWith(dirtyPaths: dirty));
    }
  }

  Future<bool> saveFile(String path) async {
    final handle = _handles[path];
    if (handle == null) return false;
    if (state.readOnlyPaths.contains(path)) {
      emit(
        state.copyWith(snackbarMessage: EditorMessage.readOnly),
      );
      return false;
    }
    try {
      await _fs.atomicWrite(path, handle.controller.text);
      handle.savedText = handle.controller.text;
      final dirty = Set<String>.from(state.dirtyPaths)..remove(path);
      emit(state.copyWith(dirtyPaths: dirty, clearSnackbar: true));
      return true;
    } on Object catch (e) {
      emit(state.copyWith(snackbarMessage: EditorMessage.saveFailed(e)));
      return false;
    }
  }

  void _disposeHandle(String path) {
    _handles.remove(path)?.dispose();
  }

  @override
  Future<void> close() async {
    for (final path in _handles.keys.toList()) {
      _disposeHandle(path);
    }
    return super.close();
  }
}
