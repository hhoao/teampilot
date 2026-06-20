import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../services/file_tree/file_tree_clipboard.dart';
import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';

class FileTreeOperationException implements Exception {
  FileTreeOperationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FileTreeState {
  const FileTreeState({
    this.rootPath = '',
    this.rootExists = false,
    this.expandedPaths = const {},
    this.filterText = '',
    this.showHiddenFiles = false,
    this.dirCache = const {},
    this.revealPath,
    this.clipboard,
  });

  final String rootPath;
  final bool rootExists;
  final Set<String> expandedPaths;
  final String filterText;
  final bool showHiddenFiles;
  final Map<String, List<FsDirEntry>> dirCache;

  /// Set by [FileTreeCubit.revealPath]; cleared after scroll-into-view.
  final String? revealPath;

  /// In-tree copy/cut source for paste.
  final FileTreeClipboard? clipboard;

  FileTreeState copyWith({
    String? rootPath,
    bool? rootExists,
    Set<String>? expandedPaths,
    String? filterText,
    bool? showHiddenFiles,
    Map<String, List<FsDirEntry>>? dirCache,
    String? revealPath,
    FileTreeClipboard? clipboard,
    bool clearRevealPath = false,
    bool clearFilter = false,
    bool clearClipboard = false,
  }) {
    return FileTreeState(
      rootPath: rootPath ?? this.rootPath,
      rootExists: rootExists ?? this.rootExists,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      filterText: clearFilter ? '' : (filterText ?? this.filterText),
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      dirCache: dirCache ?? this.dirCache,
      revealPath: clearRevealPath ? null : (revealPath ?? this.revealPath),
      clipboard: clearClipboard ? null : (clipboard ?? this.clipboard),
    );
  }
}

class FileTreeCubit extends Cubit<FileTreeState> {
  FileTreeCubit({Filesystem? fs})
    : fs = fs ?? LocalFilesystem(),
      super(const FileTreeState());

  final Filesystem fs;

  Future<void> setRoot(String path) async {
    if (path == state.rootPath) return;
    if (path.isEmpty) {
      emit(const FileTreeState());
      return;
    }
    final stat = await fs.stat(path);
    final exists = stat.exists && stat.isDirectory;
    emit(FileTreeState(rootPath: path, rootExists: exists));
    if (exists) {
      await _loadDirectory(path);
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
    emit(state.copyWith(expandedPaths: expanded));
  }

  void setFilter(String text) {
    emit(state.copyWith(filterText: text));
  }

  void toggleShowHidden() {
    // Flip the flag, then re-read visible directories in place. The new filter
    // is applied by [_fetchDirectoryEntries]; no need to flash the cache empty.
    emit(state.copyWith(showHiddenFiles: !state.showHiddenFiles));
    unawaited(refresh());
  }

  /// Re-reads every currently-visible directory (root + expanded) in place and
  /// emits once. Used by the manual refresh action and full-scope change hints.
  Future<void> refresh() {
    return _reloadDirectories({
      if (state.rootPath.isNotEmpty) state.rootPath,
      ...state.expandedPaths,
    });
  }

  /// Re-reads only the [changedDirs] that are actually visible (root or already
  /// loaded), skipping unloaded/collapsed folders. This is the targeted path
  /// for filesystem change hints — a single file write reloads just its folder
  /// instead of the whole tree.
  Future<void> refreshPaths(Set<String> changedDirs) {
    final relevant = changedDirs
        .where((d) => d == state.rootPath || state.dirCache.containsKey(d))
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
    emit(state.copyWith(dirCache: cache));
  }

  void clearRevealPath() {
    if (state.revealPath == null) return;
    emit(state.copyWith(clearRevealPath: true));
  }

  /// Expands ancestor folders and scrolls [filePath] into view in the tree.
  Future<bool> revealPath(
    String filePath, {
    bool clearFilter = true,
  }) async {
    final ctx = fs.pathContext;
    final normalized = ctx.normalize(filePath.trim());
    if (normalized.isEmpty) return false;

    final root = state.rootPath;
    if (root.isEmpty || !state.rootExists) return false;

    final rootNorm = ctx.normalize(root);
    if (!_isPathUnderRoot(ctx, rootNorm, normalized)) {
      return false;
    }

    final stat = await fs.stat(normalized);
    if (!stat.exists || stat.isDirectory) return false;

    final expanded = Set<String>.from(state.expandedPaths);
    var parent = ctx.dirname(normalized);
    while (!_pathsEqual(ctx, parent, rootNorm) &&
        _isPathUnderRoot(ctx, rootNorm, parent)) {
      expanded.add(parent);
      await _loadDirectory(parent);
      parent = ctx.dirname(parent);
    }
    await _loadDirectory(rootNorm);

    emit(
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
    emit(state.copyWith(dirCache: cache));
  }

  Future<List<FsDirEntry>?> _fetchDirectoryEntries(String path) async {
    try {
      final stat = await fs.stat(path);
      if (!stat.exists || !stat.isDirectory) return null;
      final allEntries = await fs.listDir(path);
      return allEntries.where(_matchesFilter).toList()
        ..sort(_compareEntries);
    } catch (_) {
      return null;
    }
  }

  void collapseAllFolders() {
    emit(state.copyWith(expandedPaths: const {}));
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
    await fs.removeRecursive(path);
    await refresh();
  }

  void copyItem(String path) {
    emit(
      state.copyWith(
        clipboard: FileTreeClipboard(
          path: path,
          mode: FileTreeClipboardMode.copy,
        ),
      ),
    );
  }

  void cutItem(String path) {
    emit(
      state.copyWith(
        clipboard: FileTreeClipboard(
          path: path,
          mode: FileTreeClipboardMode.cut,
        ),
      ),
    );
  }

  Future<void> pasteInto(String destDir) async {
    final clip = state.clipboard;
    if (clip == null) return;

    final ctx = fs.pathContext;
    final dest = ctx.normalize(destDir);
    final source = ctx.normalize(clip.path);
    if (!_canPasteInto(ctx, source: source, destDir: dest)) {
      throw FileTreeOperationException('invalid paste target');
    }

    final target = ctx.join(dest, ctx.basename(source));
    if (!_pathsEqual(ctx, source, target)) {
      final existing = await fs.stat(target);
      if (existing.exists) {
        throw FileTreeOperationException('target already exists');
      }
    }

    final sourceStat = await fs.stat(source);
    if (!sourceStat.exists) {
      emit(state.copyWith(clearClipboard: true));
      throw FileTreeOperationException('source missing');
    }

    if (clip.mode == FileTreeClipboardMode.copy) {
      if (sourceStat.isDirectory) {
        await fs.copyTree(source: source, destination: target);
      } else {
        await fs.copyFile(source, target);
      }
    } else {
      await fs.rename(source, target);
      emit(state.copyWith(clearClipboard: true));
    }

    final expanded = Set<String>.from(state.expandedPaths)..add(dest);
    emit(state.copyWith(expandedPaths: expanded));
    await refresh();
  }

  Future<void> renameItem(String path, String newName) async {
    final trimmed = newName.trim();
    _validateName(trimmed);

    final ctx = fs.pathContext;
    final parent = ctx.dirname(path);
    final target = ctx.join(parent, trimmed);
    if (_pathsEqual(ctx, path, target)) return;

    final existing = await fs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await fs.rename(path, target);
    await refresh();
  }

  Future<void> createFile(String parentDir, String name) async {
    final trimmed = name.trim();
    _validateName(trimmed);

    final ctx = fs.pathContext;
    final target = ctx.join(parentDir, trimmed);
    final existing = await fs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await fs.writeString(target, '');
    final expanded = Set<String>.from(state.expandedPaths)..add(parentDir);
    emit(state.copyWith(expandedPaths: expanded));
    await refresh();
  }

  Future<void> createFolder(String parentDir, String name) async {
    final trimmed = name.trim();
    _validateName(trimmed);

    final ctx = fs.pathContext;
    final target = ctx.join(parentDir, trimmed);
    final existing = await fs.stat(target);
    if (existing.exists) {
      throw FileTreeOperationException('target already exists');
    }

    await fs.ensureDir(target);
    final expanded = Set<String>.from(state.expandedPaths)..add(parentDir);
    emit(state.copyWith(expandedPaths: expanded));
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
