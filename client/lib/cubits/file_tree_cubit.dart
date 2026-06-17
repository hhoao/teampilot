import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../services/io/filesystem.dart';
import '../services/io/local_filesystem.dart';

class FileTreeState {
  const FileTreeState({
    this.rootPath = '',
    this.rootExists = false,
    this.expandedPaths = const {},
    this.filterText = '',
    this.showHiddenFiles = false,
    this.dirCache = const {},
    this.revealPath,
  });

  final String rootPath;
  final bool rootExists;
  final Set<String> expandedPaths;
  final String filterText;
  final bool showHiddenFiles;
  final Map<String, List<FsDirEntry>> dirCache;

  /// Set by [FileTreeCubit.revealPath]; cleared after scroll-into-view.
  final String? revealPath;

  FileTreeState copyWith({
    String? rootPath,
    bool? rootExists,
    Set<String>? expandedPaths,
    String? filterText,
    bool? showHiddenFiles,
    Map<String, List<FsDirEntry>>? dirCache,
    String? revealPath,
    bool clearRevealPath = false,
    bool clearFilter = false,
  }) {
    return FileTreeState(
      rootPath: rootPath ?? this.rootPath,
      rootExists: rootExists ?? this.rootExists,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      filterText: clearFilter ? '' : (filterText ?? this.filterText),
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      dirCache: dirCache ?? this.dirCache,
      revealPath: clearRevealPath ? null : (revealPath ?? this.revealPath),
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
    final show = !state.showHiddenFiles;
    final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);
    for (final key in cache.keys.toList()) {
      cache.remove(key);
    }
    emit(state.copyWith(showHiddenFiles: show, dirCache: cache));
    if (state.rootPath.isNotEmpty) {
      _loadDirectory(state.rootPath);
    }
    for (final p in state.expandedPaths) {
      _loadDirectory(p);
    }
  }

  void refresh() {
    final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);
    cache.clear();
    emit(state.copyWith(dirCache: cache));
    if (state.rootPath.isNotEmpty) {
      _loadDirectory(state.rootPath);
    }
    for (final p in state.expandedPaths) {
      _loadDirectory(p);
    }
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
    if (entries == null) return;
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

  /// True when every visible directory under [rootPath] is expanded.
  bool isAllFoldersExpanded() {
    final root = state.rootPath;
    if (root.isEmpty || !state.rootExists) return false;
    return _isDirFullyExpanded(root);
  }

  bool _isDirFullyExpanded(String dirPath) {
    final entries = state.dirCache[dirPath];
    if (entries == null) return true;
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final childPath = fs.pathContext.join(dirPath, entry.name);
      if (!state.expandedPaths.contains(childPath)) return false;
      if (!_isDirFullyExpanded(childPath)) return false;
    }
    return true;
  }

  Future<void> expandAllFolders() async {
    final root = state.rootPath;
    if (root.isEmpty || !state.rootExists) return;

    final expanded = <String>{};
    final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);

    Future<void> walk(String dirPath) async {
      var entries = cache[dirPath];
      entries ??= await _fetchDirectoryEntries(dirPath);
      if (entries == null) return;
      cache[dirPath] = entries;
      for (final entry in entries) {
        if (!entry.isDirectory) continue;
        final childPath = fs.pathContext.join(dirPath, entry.name);
        expanded.add(childPath);
        await walk(childPath);
      }
    }

    await walk(root);
    emit(state.copyWith(expandedPaths: expanded, dirCache: cache));
  }

  void collapseAllFolders() {
    emit(state.copyWith(expandedPaths: const {}));
  }

  Future<void> toggleExpandAllFolders() async {
    if (isAllFoldersExpanded()) {
      collapseAllFolders();
    } else {
      await expandAllFolders();
    }
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
    refresh();
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
