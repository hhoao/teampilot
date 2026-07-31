import 'dart:math' as math;
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../services/diff/diff_hunk_applier.dart';
import '../services/diff/diff_model.dart';
import '../services/editor/code_line_selection_for_lines.dart';
import '../services/editor/editor_messages.dart';
import '../services/editor/file_editor_theme.dart';
import '../services/editor_platform/document_session.dart';
import '../services/editor_platform/document_session_token_provider.dart';
import '../services/editor_platform/editor_platform.dart';
import '../services/editor_platform/language_registry.dart';
import '../services/editor_platform/worker_protocol.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import 'workbench/workbench_tab.dart';

class DiffTabState extends Equatable {
  const DiffTabState({
    required this.absolutePath,
    required this.source,
    required this.title,
    required this.diffText,
  });

  final String absolutePath;
  final WorkbenchDiffSource source;
  final String title;
  final String diffText;

  bool get staged => source == WorkbenchDiffSource.staged;

  String get key =>
      WorkbenchTabId.diffKey(absolutePath, source: source);

  DiffTabState copyWith({String? diffText, String? title}) {
    return DiffTabState(
      absolutePath: absolutePath,
      source: source,
      title: title ?? this.title,
      diffText: diffText ?? this.diffText,
    );
  }

  @override
  List<Object?> get props => [absolutePath, source, title, diffText];
}

class WorkspaceEditorBucket extends Equatable {
  const WorkspaceEditorBucket({
    this.openFilePaths = const [],
    this.openDiffs = const {},
    this.dirtyPaths = const {},
    this.dirtyDiffKeys = const {},
    this.loadingPaths = const {},
    this.errorByPath = const {},
    this.readOnlyPaths = const {},
  });

  final List<String> openFilePaths;
  final Map<String, DiffTabState> openDiffs;
  final Set<String> dirtyPaths;
  final Set<String> dirtyDiffKeys;
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
    Set<String>? dirtyDiffKeys,
    Set<String>? loadingPaths,
    Map<String, String>? errorByPath,
    Set<String>? readOnlyPaths,
  }) {
    return WorkspaceEditorBucket(
      openFilePaths: openFilePaths ?? this.openFilePaths,
      openDiffs: openDiffs ?? this.openDiffs,
      dirtyPaths: dirtyPaths ?? this.dirtyPaths,
      dirtyDiffKeys: dirtyDiffKeys ?? this.dirtyDiffKeys,
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
    dirtyDiffKeys,
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

  /// Tree-sitter syntax state for this document (null for plain-text files or
  /// while still loading).
  DocumentSession? session;

  /// Adapter exposing [session]'s tokens to re-editor.
  DocumentSessionTokenProvider? tokenProvider;

  /// Snapshot of the controller text after the last processed change, used to
  /// derive the incremental code-unit edit forwarded to [session].
  String _previousText = '';

  /// Stable per-file identity for the [CodeEditor] element.
  final GlobalKey editorKey = GlobalKey(debugLabel: 'file-editor');

  void attachListener() {
    _listener ??= () {
      final newText = controller.text;
      if (newText != _previousText) {
        _forwardEditToSession(_previousText, newText);
        _previousText = newText;
      }
      if (savedText != null && newText != savedText) {
        onDirty();
      }
    };
    controller.addListener(_listener!);
  }

  /// Computes the minimal code-unit replacement between [oldText] and [newText]
  /// (longest common prefix/suffix) and mirrors it to the tree-sitter session.
  void _forwardEditToSession(String oldText, String newText) {
    final session = this.session;
    if (session == null) return;

    final oldLen = oldText.length;
    final newLen = newText.length;
    final maxCommon = oldLen < newLen ? oldLen : newLen;

    var prefix = 0;
    while (prefix < maxCommon &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    var suffix = 0;
    final maxSuffix = maxCommon - prefix;
    while (suffix < maxSuffix &&
        oldText.codeUnitAt(oldLen - 1 - suffix) ==
            newText.codeUnitAt(newLen - 1 - suffix)) {
      suffix++;
    }

    final deleteCount = oldLen - prefix - suffix;
    final insert = newText.substring(prefix, newLen - suffix);
    if (deleteCount == 0 && insert.isEmpty) return;

    session.applyEdit(
      codeUnitStart: prefix,
      codeUnitDeleteCount: deleteCount,
      insert: insert,
    );
  }

  void dispose() {
    if (_listener != null) {
      controller.removeListener(_listener!);
    }
    controller.dispose();
    tokenProvider?.dispose();
    session?.dispose();
    tokenProvider = null;
    session = null;
  }
}

typedef DiffReload =
    Future<String?> Function(bool ignoreWhitespace, bool fullContext);

class _WritableDiffHandle {
  _WritableDiffHandle({
    required this.lastLoadedCanonical,
    required this.canonical,
    required this.absolutePath,
    required this.diffKey,
  });

  String lastLoadedCanonical;
  String canonical;
  final String absolutePath;
  final String diffKey;

  bool get isDirty => canonical != lastLoadedCanonical;
}

class EditorCubit extends Cubit<EditorState> {
  EditorCubit({
    Filesystem? fs,
    TsWorkerPool? workerPool,
    LanguageRegistry? languageRegistry,
  })  : _fs = fs ?? AppStorage.fs,
        _injectedPool = workerPool,
        _injectedRegistry = languageRegistry,
        super(const EditorState());

  final Filesystem _fs;

  /// Injected in tests; falls back to the shared [EditorPlatform] pool/registry
  /// in the app. Resolved lazily so tests that never open a highlighted file do
  /// not construct the native [EditorPlatform.workerPool].
  final TsWorkerPool? _injectedPool;
  final LanguageRegistry? _injectedRegistry;

  final Map<String, Filesystem> _fsByHandle = {};
  final Map<String, _OpenFileHandle> _handles = {};
  final Map<String, Uint8List> _imageBytes = {};
  final Map<String, DiffReload> _diffReloadByKey = {};
  final Map<String, _WritableDiffHandle> _writableDiffs = {};
  final Map<String, Future<void> Function()?> _onWorkingTreeWritten = {};

  TsWorkerPool get _pool => _injectedPool ?? EditorPlatform.workerPool;
  LanguageRegistry get _registry => _injectedRegistry ?? EditorPlatform.registry;

  String _handleKey(String workspaceId, String path) => '$workspaceId\x00$path';

  CodeLineEditingController? controllerFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.controller;

  /// Selects an inclusive 1-based line range in an open file.
  ///
  /// v1 sets [CodeLineEditingController.selection] only; scroll-into-view is not
  /// guaranteed.
  void selectLines(
    String workspaceId,
    String path, {
    required int startLine,
    int? endLine,
  }) {
    final controller = controllerFor(workspaceId, path);
    if (controller == null) return;

    final lines = controller.codeLines;
    final lineCount = lines.length;
    final lineLengths = List<int>.generate(lineCount, (i) => lines[i].length);
    controller.selection = codeLineSelectionForLines(
      lineCount: lineCount,
      lineLengths: lineLengths,
      startLine: startLine,
      endLine: endLine,
    );
  }

  GlobalKey? editorKeyFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.editorKey;

  /// Loaded image bytes for an open preview tab, or null when not an image /
  /// not open.
  Uint8List? bytesFor(String workspaceId, String path) =>
      _imageBytes[_handleKey(workspaceId, path)];

  /// Syntax token provider for an open file, or null when the file is plain
  /// text, still loading, or not open.
  CodeTokenProvider? tokenProviderFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.tokenProvider;

  /// The live [DocumentSession] for an open file, used by the viewport binder to
  /// request tokens for newly visible lines. Null for plain text / not open.
  DocumentSession? documentSessionFor(String workspaceId, String path) =>
      _handles[_handleKey(workspaceId, path)]?.session;

  bool isReadOnly(String workspaceId, String path) =>
      state.bucket(workspaceId).readOnlyPaths.contains(path);

  DiffReload? diffReloadFor(String diffKey) => _diffReloadByKey[diffKey];

  Future<void> Function()? onWorkingTreeWrittenFor(String diffKey) =>
      _onWorkingTreeWritten[diffKey];

  Future<String> readWorkingTreeText(String absolutePath) async {
    final content = await _fs.readString(absolutePath);
    return content ?? '';
  }

  bool isDiffWritable(String diffKey) => _writableDiffs.containsKey(diffKey);

  bool isDiffDirty(String diffKey) => _writableDiffs[diffKey]?.isDirty ?? false;

  String? diffCanonicalFor(String diffKey) => _writableDiffs[diffKey]?.canonical;

  Future<void> bindWritableDiff({
    required String workspaceId,
    required String diffKey,
    required String absolutePath,
    required String lastLoadedCanonical,
    Future<void> Function()? onWorkingTreeWritten,
  }) async {
    final existing = _writableDiffs[diffKey];
    if (existing != null && existing.isDirty) {
      existing.lastLoadedCanonical = lastLoadedCanonical;
    } else {
      _writableDiffs[diffKey] = _WritableDiffHandle(
        lastLoadedCanonical: lastLoadedCanonical,
        canonical: lastLoadedCanonical,
        absolutePath: absolutePath,
        diffKey: diffKey,
      );
    }
    if (onWorkingTreeWritten != null) {
      _onWorkingTreeWritten[diffKey] = onWorkingTreeWritten;
    }
    _syncDirtyDiffKey(workspaceId, diffKey);
  }

  void updateDiffCanonical(String diffKey, String canonical) {
    final handle = _writableDiffs[diffKey];
    if (handle == null) return;
    handle.canonical = canonical;
    for (final workspaceId in state.byWorkspace.keys) {
      if (state.bucket(workspaceId).openDiffs.containsKey(diffKey)) {
        _syncDirtyDiffKey(workspaceId, diffKey);
        return;
      }
    }
  }

  Future<bool> applyDiffHunk({
    required String workspaceId,
    required String diffKey,
    required DiffResult result,
    required DiffBlock block,
    required bool discardDirtyIfNeeded,
  }) async {
    final handle = _writableDiffs[diffKey];
    if (handle == null) return false;
    if (handle.isDirty && !discardDirtyIfNeeded) return false;
    final baseCanonical = handle.isDirty && discardDirtyIfNeeded
        ? handle.lastLoadedCanonical
        : handle.canonical;
    final next = DiffHunkApplier.applyLeftToRight(
      result: result,
      block: block,
      rightFileText: baseCanonical,
    );
    return _commitWorkingTreeWrite(
      workspaceId: workspaceId,
      diffKey: diffKey,
      nextCanonical: next,
      writeFailureMessagePrefix: 'diffApplyFailed',
    );
  }

  Future<bool> saveDiffWorkingTree(String workspaceId, String diffKey) async {
    final handle = _writableDiffs[diffKey];
    if (handle == null) return false;
    return _commitWorkingTreeWrite(
      workspaceId: workspaceId,
      diffKey: diffKey,
      nextCanonical: handle.canonical,
      writeFailureMessagePrefix: 'diffSaveFailed',
    );
  }

  void clearWritableDiff(String diffKey) {
    final workspaceId = _workspaceIdForDiffKey(diffKey);
    _writableDiffs.remove(diffKey);
    _onWorkingTreeWritten.remove(diffKey);
    if (workspaceId != null) {
      _syncDirtyDiffKey(workspaceId, diffKey);
    }
  }

  Future<bool> retryDiffReload(String workspaceId, String diffKey) async {
    final reloaded = await _reloadDiffAfterWrite(workspaceId, diffKey);
    if (reloaded) {
      emit(state.copyWith(clearSnackbar: true));
    }
    return reloaded;
  }

  bool anyWritableDiffDirtyFor(String workspaceId, String absolutePath) {
    final bucket = state.bucket(workspaceId);
    for (final diffKey in bucket.openDiffs.keys) {
      final handle = _writableDiffs[diffKey];
      if (handle == null) continue;
      if (handle.absolutePath != absolutePath) continue;
      if (handle.isDirty) return true;
    }
    return false;
  }

  void clearSnackbarMessage() {
    if (state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbar: true));
  }

  /// Records a decode failure for an open image preview tab.
  void reportImageDecodeFailed(String workspaceId, String path) {
    final bucket = state.bucket(workspaceId);
    if (!bucket.openFilePaths.contains(path)) return;
    final errors = Map<String, String>.from(bucket.errorByPath)
      ..[path] = EditorMessage.imageDecodeFailed;
    emit(
      state
          .withBucket(workspaceId, bucket.copyWith(errorByPath: errors))
          .copyWith(snackbarMessage: EditorMessage.imageDecodeFailed),
    );
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

    final isImage = isImagePreviewPath(normalized);
    if (!isImage && !isEditorOpenableFilePath(normalized)) {
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

      if (isImage) {
        if (size > kEditorMaxImageBytes) {
          emit(
            _clearLoading(
              workspaceId,
              normalized,
              error: EditorMessage.imageTooLarge,
            ),
          );
          return;
        }

        final bytes = await filesystem.readBytes(normalized);
        if (!_stillLoading(workspaceId, normalized)) return;
        if (bytes == null) {
          emit(
            _clearLoading(
              workspaceId,
              normalized,
              error: EditorMessage.couldNotRead,
            ),
          );
          return;
        }
        // WSL/SFTP may omit FsStat.size; reject after read if over the cap.
        if (bytes.length > kEditorMaxImageBytes) {
          emit(
            _clearLoading(
              workspaceId,
              normalized,
              error: EditorMessage.imageTooLarge,
            ),
          );
          return;
        }

        final key = _handleKey(workspaceId, normalized);
        _imageBytes[key] =
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

        final current = state.bucket(workspaceId);
        if (!current.loadingPaths.contains(normalized)) {
          _imageBytes.remove(key);
          return;
        }
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
        return;
      }

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
      )
        ..savedText = content
        .._previousText = content;
      _handles[key] = handle;
      _fsByHandle[key] = filesystem;

      final session = DocumentSession(registry: _registry, pool: _pool);
      handle.session = session;
      handle.tokenProvider = DocumentSessionTokenProvider(session);

      await session.open(path: normalized, text: content);
      if (!_stillLoading(workspaceId, normalized) ||
          _handles[key] != handle) {
        return;
      }
      await session.colorizeAfterOpen(
        viewportEndLine: math.min(80, session.lineCount - 1),
      );
      if (!_stillLoading(workspaceId, normalized) ||
          _handles[key] != handle) {
        return;
      }

      handle.attachListener();

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
      // A handle may have been registered before an await threw; drop it so its
      // session/controller are not leaked (the file never became "open").
      if (!state.bucket(workspaceId).openFilePaths.contains(normalized)) {
        _disposeHandle(workspaceId, normalized);
      }
      if (!_stillLoading(workspaceId, normalized)) return;
      emit(_clearLoading(workspaceId, normalized, error: e.toString()));
    }
  }

  bool _stillLoading(String workspaceId, String path) =>
      state.bucket(workspaceId).loadingPaths.contains(path);

  void openDiff({
    required String workspaceId,
    required String absolutePath,
    required WorkbenchDiffSource source,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
    Future<void> Function()? onWorkingTreeWritten,
  }) {
    final key = WorkbenchTabId.diffKey(absolutePath, source: source);
    final bucket = state.bucket(workspaceId);
    final tab = DiffTabState(
      absolutePath: absolutePath,
      source: source,
      title: title,
      diffText: diffText,
    );
    if (reloadDiff != null) {
      _diffReloadByKey[key] = reloadDiff;
    }
    if (onWorkingTreeWritten != null) {
      _onWorkingTreeWritten[key] = onWorkingTreeWritten;
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
    clearWritableDiff(diffKey);
    _diffReloadByKey.remove(diffKey);
    final current = state.bucket(workspaceId);
    final diffs = Map<String, DiffTabState>.from(current.openDiffs)
      ..remove(diffKey);
    emit(state.withBucket(workspaceId, current.copyWith(openDiffs: diffs)));
  }

  Future<bool> _commitWorkingTreeWrite({
    required String workspaceId,
    required String diffKey,
    required String nextCanonical,
    required String writeFailureMessagePrefix,
  }) async {
    final handle = _writableDiffs[diffKey];
    if (handle == null) return false;
    try {
      await _fs.atomicWrite(handle.absolutePath, nextCanonical);
    } on Object catch (e) {
      emit(state.copyWith(
        snackbarMessage: '$writeFailureMessagePrefix: $e',
      ));
      return false;
    }

    handle.lastLoadedCanonical = nextCanonical;
    handle.canonical = nextCanonical;
    _syncDirtyDiffKey(workspaceId, diffKey);

    await _reloadDiffAfterWrite(workspaceId, diffKey);

    _syncFileHandleFromText(
      workspaceId,
      handle.absolutePath,
      nextCanonical,
      notifyIfDiscardedFileDirty: true,
    );

    final callback = _onWorkingTreeWritten[diffKey];
    if (callback != null) {
      await callback();
    }
    return true;
  }

  Future<bool> _reloadDiffAfterWrite(String workspaceId, String diffKey) async {
    final reload = _diffReloadByKey[diffKey];
    if (reload == null) return true;
    try {
      final newDiff = await reload(false, false);
      if (newDiff == null) {
        emit(state.copyWith(snackbarMessage: 'diffReloadAfterSaveFailed'));
        return false;
      }
      updateDiffText(workspaceId, diffKey, newDiff);
      return true;
    } on Object {
      emit(state.copyWith(snackbarMessage: 'diffReloadAfterSaveFailed'));
      return false;
    }
  }

  String? _workspaceIdForDiffKey(String diffKey) {
    for (final entry in state.byWorkspace.entries) {
      if (entry.value.openDiffs.containsKey(diffKey)) {
        return entry.key;
      }
    }
    return null;
  }

  void _syncDirtyDiffKey(String workspaceId, String diffKey) {
    final handle = _writableDiffs[diffKey];
    final bucket = state.bucket(workspaceId);
    final dirty = Set<String>.from(bucket.dirtyDiffKeys);
    if (handle != null && handle.isDirty) {
      dirty.add(diffKey);
    } else {
      dirty.remove(diffKey);
    }
    if (dirty.length != bucket.dirtyDiffKeys.length ||
        !dirty.containsAll(bucket.dirtyDiffKeys)) {
      emit(state.withBucket(workspaceId, bucket.copyWith(dirtyDiffKeys: dirty)));
    }
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

  Future<bool> saveFile(
    String workspaceId,
    String path, {
    bool discardDiffDirty = false,
  }) async {
    final handle = _handles[_handleKey(workspaceId, path)];
    if (handle == null) return false;
    if (state.bucket(workspaceId).readOnlyPaths.contains(path)) {
      emit(state.copyWith(snackbarMessage: EditorMessage.readOnly));
      return false;
    }
    if (anyWritableDiffDirtyFor(workspaceId, path) && !discardDiffDirty) {
      return false;
    }
    final fs = _fsByHandle[_handleKey(workspaceId, path)] ?? _fs;
    final savedText = handle.controller.text;
    try {
      await fs.atomicWrite(path, savedText);
      handle.savedText = savedText;
      final bucket = state.bucket(workspaceId);
      final dirty = Set<String>.from(bucket.dirtyPaths)..remove(path);
      emit(
        state
            .withBucket(workspaceId, bucket.copyWith(dirtyPaths: dirty))
            .copyWith(clearSnackbar: true),
      );
      await _reloadDiffsForPath(workspaceId, path, savedText);
      return true;
    } on Object catch (e) {
      emit(state.copyWith(snackbarMessage: EditorMessage.saveFailed(e)));
      return false;
    }
  }

  void _syncFileHandleFromText(
    String workspaceId,
    String path,
    String text, {
    bool notifyIfDiscardedFileDirty = false,
  }) {
    final fileHandle = _handles[_handleKey(workspaceId, path)];
    if (fileHandle == null) return;

    final bucket = state.bucket(workspaceId);
    final wasFileDirty = bucket.dirtyPaths.contains(path);
    fileHandle.controller.text = text;
    fileHandle.savedText = text;

    final dirty = Set<String>.from(bucket.dirtyPaths)..remove(path);
    final snackbar = notifyIfDiscardedFileDirty && wasFileDirty
        ? 'diffFileReloadedAfterDiffWrite'
        : state.snackbarMessage;
    emit(
      state
          .withBucket(workspaceId, bucket.copyWith(dirtyPaths: dirty))
          .copyWith(snackbarMessage: snackbar),
    );
  }

  Future<void> _reloadDiffsForPath(
    String workspaceId,
    String absolutePath,
    String diskText,
  ) async {
    final bucket = state.bucket(workspaceId);
    for (final diffKey in bucket.openDiffs.keys) {
      final diffHandle = _writableDiffs[diffKey];
      if (diffHandle == null || diffHandle.absolutePath != absolutePath) {
        continue;
      }
      diffHandle.lastLoadedCanonical = diskText;
      diffHandle.canonical = diskText;
      _syncDirtyDiffKey(workspaceId, diffKey);
      await _reloadDiffAfterWrite(workspaceId, diffKey);
    }
  }

  void _disposeHandle(String workspaceId, String path) {
    final key = _handleKey(workspaceId, path);
    _fsByHandle.remove(key);
    _imageBytes.remove(key);
    _handles.remove(key)?.dispose();
  }

  @override
  Future<void> close() async {
    for (final key in _handles.keys.toList()) {
      _handles.remove(key)?.dispose();
    }
    _fsByHandle.clear();
    _imageBytes.clear();
    _diffReloadByKey.clear();
    _writableDiffs.clear();
    _onWorkingTreeWritten.clear();
    return super.close();
  }
}
