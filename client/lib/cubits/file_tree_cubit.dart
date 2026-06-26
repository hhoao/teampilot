import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../services/file_tree/file_tree_clipboard.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';
import '../services/storage/runtime_context.dart';
import 'file_tree_root_mount.dart';

class FileTreeOperationException implements Exception {
  FileTreeOperationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One workspace folder root shown in the tree. A multi-folder workspace
/// (`Workspace.folders` / `folderPaths`) yields several of these.
@immutable
class FileTreeRoot {
  const FileTreeRoot({required this.path, required this.exists});

  final String path;
  final bool exists;

  @override
  bool operator ==(Object other) =>
      other is FileTreeRoot && other.path == path && other.exists == exists;

  @override
  int get hashCode => Object.hash(path, exists);
}

class FileTreeState {
  const FileTreeState({
    this.roots = const [],
    this.expandedPaths = const {},
    this.filterText = '',
    this.showHiddenFiles = false,
    this.dirCache = const {},
    this.visibleRows = const [],
    this.revealPath,
    this.clipboard,
  });

  /// Single-root convenience constructor (most callers/tests).
  factory FileTreeState.single({
    required String rootPath,
    required bool rootExists,
    Set<String> expandedPaths = const {},
    String filterText = '',
    bool showHiddenFiles = false,
    Map<String, List<FsDirEntry>> dirCache = const {},
    List<FileTreeVisibleRow> visibleRows = const [],
    String? revealPath,
    FileTreeClipboard? clipboard,
  }) {
    return FileTreeState(
      roots: rootPath.isEmpty
          ? const []
          : [FileTreeRoot(path: rootPath, exists: rootExists)],
      expandedPaths: expandedPaths,
      filterText: filterText,
      showHiddenFiles: showHiddenFiles,
      dirCache: dirCache,
      visibleRows: visibleRows,
      revealPath: revealPath,
      clipboard: clipboard,
    );
  }

  final List<FileTreeRoot> roots;
  final Set<String> expandedPaths;
  final String filterText;
  final bool showHiddenFiles;
  final Map<String, List<FsDirEntry>> dirCache;
  final List<FileTreeVisibleRow> visibleRows;

  /// Set by [FileTreeCubit.revealPath]; cleared after scroll-into-view.
  final String? revealPath;

  /// In-tree copy/cut source for paste.
  final FileTreeClipboard? clipboard;

  /// More than one workspace folder is mounted → render per-root header rows.
  bool get isMultiRoot => roots.length > 1;

  /// True when at least one root directory exists on disk.
  bool get anyRootExists => roots.any((r) => r.exists);

  List<String> get rootPaths => [for (final r in roots) r.path];

  /// Primary (first) root path; empty when no roots. Single-root convenience.
  String get rootPath => roots.isEmpty ? '' : roots.first.path;

  /// Whether the primary root exists. Single-root convenience.
  bool get rootExists => roots.isNotEmpty && roots.first.exists;

  FileTreeState copyWith({
    List<FileTreeRoot>? roots,
    Set<String>? expandedPaths,
    String? filterText,
    bool? showHiddenFiles,
    Map<String, List<FsDirEntry>>? dirCache,
    List<FileTreeVisibleRow>? visibleRows,
    String? revealPath,
    FileTreeClipboard? clipboard,
    bool clearRevealPath = false,
    bool clearFilter = false,
    bool clearClipboard = false,
  }) {
    return FileTreeState(
      roots: roots ?? this.roots,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      filterText: clearFilter ? '' : (filterText ?? this.filterText),
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      dirCache: dirCache ?? this.dirCache,
      visibleRows: visibleRows ?? this.visibleRows,
      revealPath: clearRevealPath ? null : (revealPath ?? this.revealPath),
      clipboard: clearClipboard ? null : (clipboard ?? this.clipboard),
    );
  }
}

class FileTreeCubit extends Cubit<FileTreeState> {
  FileTreeCubit({Filesystem? fs})
    : _defaultFs = fs ?? LocalFilesystem(),
      super(const FileTreeState());

  static const _filterDebounce = Duration(milliseconds: 200);

  final Filesystem _defaultFs;
  final Map<String, FileTreeRootMount> _mountsByRoot = {};
  Timer? _filterDebounceTimer;
  String _pendingFilter = '';

  /// Primary filesystem (first mount, else constructor default).
  Filesystem get fs =>
      _mountsByRoot.isNotEmpty
          ? _mountsByRoot.values.first.filesystem
          : _defaultFs;

  Filesystem fsFor(String path) {
    final mount = _mountFor(path);
    return mount?.filesystem ?? _defaultFs;
  }

  RuntimeContext? workContextFor(String path) => _mountFor(path)?.workContext;

  @override
  Future<void> close() {
    _filterDebounceTimer?.cancel();
    return super.close();
  }

  void _publish(FileTreeState next, {bool recomputeRows = true}) {
    if (recomputeRows) {
      emit(
        next.copyWith(
          visibleRows: visibleFileTreeRows(
            state: next,
            pathContextFor: (path) => fsFor(path).pathContext,
          ),
        ),
      );
      return;
    }
    emit(next.copyWith(visibleRows: state.visibleRows));
  }

  FileTreeRootMount? _mountFor(String path) {
    if (_mountsByRoot.isEmpty) return null;
    FileTreeRootMount? best;
    var bestLen = -1;
    for (final entry in _mountsByRoot.entries) {
      final root = entry.key;
      final ctx = entry.value.filesystem.pathContext;
      final normalized = ctx.normalize(path.trim());
      if (!_isPathUnderRoot(ctx, root, normalized) &&
          !_pathsEqual(ctx, root, normalized)) {
        continue;
      }
      if (root.length > bestLen) {
        best = entry.value;
        bestLen = root.length;
      }
    }
    return best;
  }

  bool _mountMapsEqual(
    Map<String, FileTreeRootMount> a,
    Map<String, FileTreeRootMount> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !identical(other.filesystem, entry.value.filesystem)) {
        return false;
      }
    }
    return true;
  }

  /// Single-root convenience wrapper around [mountRoots].
  Future<void> setRoot(String path) =>
      mountRoots(path.isEmpty ? const [] : [FileTreeRootMount(path: path, filesystem: fs)]);

  /// Mounts [paths] on a single [filesystem] (legacy single-target callers).
  Future<void> setRoots(List<String> paths, {Filesystem? filesystem}) {
    final activeFs = filesystem ?? fs;
    return mountRoots([
      for (final path in paths)
        if (path.isNotEmpty)
          FileTreeRootMount(path: path, filesystem: activeFs),
    ]);
  }

  /// Mounts workspace folder roots, each with its own work-plane [Filesystem].
  Future<void> mountRoots(List<FileTreeRootMount> mounts) async {
    final wanted = <String, FileTreeRootMount>{};
    for (final mount in mounts) {
      final path = mount.path.trim();
      if (path.isEmpty) continue;
      final ctx = mount.filesystem.pathContext;
      wanted[ctx.normalize(path)] = FileTreeRootMount(
        path: ctx.normalize(path),
        filesystem: mount.filesystem,
        workContext: mount.workContext,
      );
    }
    if (_mountMapsEqual(wanted, _mountsByRoot)) return;
    _mountsByRoot
      ..clear()
      ..addAll(wanted);
    final paths = wanted.keys.toList(growable: false);
    if (paths.isEmpty) {
      _publish(const FileTreeState());
      return;
    }
    final roots = <FileTreeRoot>[];
    for (final path in paths) {
      final activeFs = wanted[path]!.filesystem;
      final stat = await activeFs.stat(path);
      roots.add(
        FileTreeRoot(path: path, exists: stat.exists && stat.isDirectory),
      );
    }
    final expanded = roots.length > 1
        ? {for (final r in roots) if (r.exists) r.path}
        : <String>{};
    _publish(FileTreeState(roots: roots, expandedPaths: expanded));
    for (final root in roots) {
      if (root.exists) await _loadDirectory(root.path);
    }
  }

  void toggleExpand(String path) {
    final expanded = Set<String>.from(state.expandedPaths);
    if (expanded.contains(path)) {
      expanded.remove(path);
    } else {
      expanded.add(path);
      _loadDirectory(path);
    }
    _publish(state.copyWith(expandedPaths: expanded));
  }

  void setFilter(String text) {
    _pendingFilter = text;
    _filterDebounceTimer?.cancel();
    if (text.isEmpty) {
      _applyFilter('');
      return;
    }
    _filterDebounceTimer = Timer(_filterDebounce, () {
      if (isClosed) return;
      _applyFilter(_pendingFilter);
    });
  }

  void _applyFilter(String text) {
    if (text == state.filterText) return;
    _publish(state.copyWith(filterText: text));
    unawaited(refresh());
  }

  void toggleShowHidden() {
    // Flip the flag, then re-read visible directories in place. The new filter
    // is applied by [_fetchDirectoryEntries]; no need to flash the cache empty.
    _publish(state.copyWith(showHiddenFiles: !state.showHiddenFiles));
    unawaited(refresh());
  }

  /// Re-reads every currently-visible directory (root + expanded) in place and
  /// emits once. Used by the manual refresh action and full-scope change hints.
  Future<void> refresh() {
    return _reloadDirectories({
      ...state.rootPaths.where((p) => p.isNotEmpty),
      ...state.expandedPaths,
    });
  }

  /// Re-reads only the [changedDirs] that are actually visible (root or already
  /// loaded), skipping unloaded/collapsed folders. This is the targeted path
  /// for filesystem change hints — a single file write reloads just its folder
  /// instead of the whole tree.
  Future<void> refreshPaths(Set<String> changedDirs) {
    final relevant = changedDirs
        .where(
          (d) => state.rootPaths.contains(d) || state.dirCache.containsKey(d),
        )
        .toSet();
    if (relevant.isEmpty) return Future<void>.value();
    return _reloadDirectories(relevant);
  }

  /// Reloads [paths] concurrently and applies all results in a single [emit] —
  /// no intermediate empty state (no flicker), one rebuild. A directory that no
  /// longer exists is dropped from the cache.
  Future<void> _reloadDirectories(Set<String> paths) async {
    if (paths.isEmpty) return;
    final loaded = await Future.wait(
      paths.map(
        (path) async => MapEntry(path, await _fetchDirectoryEntries(path)),
      ),
    );
    if (isClosed) return;
    final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);
    for (final entry in loaded) {
      if (entry.value != null) {
        cache[entry.key] = entry.value!;
      } else {
        cache.remove(entry.key);
      }
    }
    _publish(state.copyWith(dirCache: cache));
  }

  void clearRevealPath() {
    if (state.revealPath == null) return;
    _publish(state.copyWith(clearRevealPath: true), recomputeRows: false);
  }

  /// Expands ancestor folders and scrolls [filePath] into view in the tree.
  Future<bool> revealPath(
    String filePath, {
    bool clearFilter = true,
  }) async {
    final normalized = fsFor(filePath).pathContext.normalize(filePath.trim());
    if (normalized.isEmpty) return false;

    String? rootNorm;
    p.Context? rootCtx;
    for (final root in state.roots) {
      if (!root.exists) continue;
      final ctx = fsFor(root.path).pathContext;
      final candidate = ctx.normalize(root.path);
      if (_isPathUnderRoot(ctx, candidate, normalized)) {
        rootNorm = candidate;
        rootCtx = ctx;
        break;
      }
    }
    if (rootNorm == null || rootCtx == null) return false;

    final activeFs = fsFor(normalized);
    final stat = await activeFs.stat(normalized);
    if (!stat.exists || stat.isDirectory) return false;

    final expanded = Set<String>.from(state.expandedPaths);
    if (state.isMultiRoot) expanded.add(rootNorm);
    var parent = rootCtx.dirname(normalized);
    while (!_pathsEqual(rootCtx, parent, rootNorm) &&
        _isPathUnderRoot(rootCtx, rootNorm, parent)) {
      expanded.add(parent);
      await _loadDirectory(parent);
      parent = rootCtx.dirname(parent);
    }
    await _loadDirectory(rootNorm);

    _publish(
      state.copyWith(
        expandedPaths: expanded,
        revealPath: normalized,
        clearFilter: clearFilter,
      ),
    );
    return true;
  }

  Future<void> _loadDirectory(String path) async {
    final entries = await _fetchDirectoryEntries(path);
    if (isClosed || entries == null) return;
    final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);
    cache[path] = entries;
    _publish(state.copyWith(dirCache: cache));
  }

  Future<List<FsDirEntry>?> _fetchDirectoryEntries(String path) async {
    final activeFs = fsFor(path);
    try {
      final stat = await activeFs.stat(path);
      if (!stat.exists || !stat.isDirectory) return null;
      final allEntries = await activeFs.listDir(path);
      return allEntries.where(_matchesFilter).toList()
        ..sort(_compareEntries);
    } catch (_) {
      return null;
    }
  }

  void collapseAllFolders() {
    _publish(state.copyWith(expandedPaths: const {}));
  }

  List<FsDirEntry> entriesFor(String path) {
    return state.dirCache[path] ?? [];
  }

  bool _matchesFilter(FsDirEntry entry) {
    if (!state.showHiddenFiles && entry.name.startsWith('.')) return false;
    if (state.filterText.isNotEmpty &&
        !entry.name.toLowerCase().contains(state.filterText.toLowerCase())) {
      return false;
    }
    return true;
  }

  static int _compareEntries(FsDirEntry a, FsDirEntry b) {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Deletes a file or directory at [path] and refreshes the tree.
  Future<void> deletePath(String path) async {
    await fsFor(path).removeRecursive(path);
    await refresh();
  }

  void copyItem(String path) {
    _publish(
      state.copyWith(
        clipboard: FileTreeClipboard(
          path: path,
          mode: FileTreeClipboardMode.copy,
        ),
      ),
      recomputeRows: false,
    );
  }

  void cutItem(String path) {
    _publish(
      state.copyWith(
        clipboard: FileTreeClipboard(
          path: path,
          mode: FileTreeClipboardMode.cut,
        ),
      ),
      recomputeRows: false,
    );
  }

  Future<void> pasteInto(String destDir) async {
    final clip = state.clipboard;
    if (clip == null) return;

    final ctx = fsFor(destDir).pathContext;
    final dest = ctx.normalize(destDir);
    final source = ctx.normalize(clip.path);
    if (!_canPasteInto(ctx, source: source, destDir: dest)) {
      throw FileTreeOperationException('invalid paste target');
    }

    final target = ctx.join(dest, ctx.basename(source));
    final activeFs = fsFor(destDir);
    if (!_pathsEqual(ctx, source, target)) {
      final existing = await activeFs.stat(target);
      if (existing.exists) {
        throw FileTreeOperationException('target already exists');
      }
    }

    final sourceStat = await fsFor(source).stat(source);
    if (!sourceStat.exists) {
      _publish(state.copyWith(clearClipboard: true));
      throw FileTreeOperationException('source missing');
    }

    if (clip.mode == FileTreeClipboardMode.copy) {
      if (sourceStat.isDirectory) {
        await activeFs.copyTree(source: source, destination: target);
      } else {
        await activeFs.copyFile(source, target);
      }
    } else {
      await fsFor(source).rename(source, target);
      _publish(state.copyWith(clearClipboard: true));
    }

    final expanded = Set<String>.from(state.expandedPaths)..add(dest);
    _publish(state.copyWith(expandedPaths: expanded));
    await refresh();
  }

  Future<void> renameItem(String path, String newName) async {
    final trimmed = newName.trim();
    _validateName(trimmed);

    final activeFs = fsFor(path);
    final ctx = activeFs.pathContext;
    final parent = ctx.dirname(path);
    final target = ctx.join(parent, trimmed);
    if (_pathsEqual(ctx, path, target)) return;

    final existing = await activeFs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await activeFs.rename(path, target);
    await refresh();
  }

  Future<void> createFile(String parentDir, String name) async {
    final trimmed = name.trim();
    _validateName(trimmed);

    final activeFs = fsFor(parentDir);
    final ctx = activeFs.pathContext;
    final target = ctx.join(parentDir, trimmed);
    final existing = await activeFs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await activeFs.writeString(target, '');
    final expanded = Set<String>.from(state.expandedPaths)..add(parentDir);
    _publish(state.copyWith(expandedPaths: expanded));
    await refresh();
  }

  Future<void> createFolder(String parentDir, String name) async {
    final trimmed = name.trim();
    _validateName(trimmed);

    final activeFs = fsFor(parentDir);
    final ctx = activeFs.pathContext;
    final target = ctx.join(parentDir, trimmed);
    final existing = await activeFs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await activeFs.ensureDir(target);
    final expanded = Set<String>.from(state.expandedPaths)..add(parentDir);
    _publish(state.copyWith(expandedPaths: expanded));
    await refresh();
  }

  static void _validateName(String name) {
    if (name.isEmpty || name == '.' || name == '..') {
      throw FileTreeOperationException('invalid name');
    }
    if (name.contains('/') || name.contains(r'\')) {
      throw FileTreeOperationException('invalid name');
    }
  }

  static bool _canPasteInto(
    p.Context ctx, {
    required String source,
    required String destDir,
  }) {
    if (_pathsEqual(ctx, source, destDir)) return false;
    try {
      if (ctx.isWithin(source, destDir)) return false;
    } catch (_) {
      final normalizedSource = source.toLowerCase();
      final normalizedDest = destDir.toLowerCase();
      final sep = ctx.separator;
      if (normalizedDest.startsWith('$normalizedSource$sep')) return false;
    }
    return true;
  }
}

bool _pathsEqual(p.Context ctx, String a, String b) {
  final left = ctx.normalize(a);
  final right = ctx.normalize(b);
  if (ctx.equals(left, right)) return true;
  return left.toLowerCase() == right.toLowerCase();
}

bool _isPathUnderRoot(p.Context ctx, String root, String path) {
  if (_pathsEqual(ctx, path, root)) return true;
  try {
    return ctx.isWithin(root, path);
  } catch (_) {
    final normalizedRoot = root.toLowerCase();
    final normalizedPath = path.toLowerCase();
    final sep = ctx.separator;
    return normalizedPath.startsWith('$normalizedRoot$sep');
  }
}
