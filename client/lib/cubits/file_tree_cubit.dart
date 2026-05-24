import 'package:flutter_bloc/flutter_bloc.dart';

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
  });

  final String rootPath;
  final bool rootExists;
  final Set<String> expandedPaths;
  final String filterText;
  final bool showHiddenFiles;
  final Map<String, List<FsDirEntry>> dirCache;

  FileTreeState copyWith({
    String? rootPath,
    bool? rootExists,
    Set<String>? expandedPaths,
    String? filterText,
    bool? showHiddenFiles,
    Map<String, List<FsDirEntry>>? dirCache,
  }) {
    return FileTreeState(
      rootPath: rootPath ?? this.rootPath,
      rootExists: rootExists ?? this.rootExists,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      filterText: filterText ?? this.filterText,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      dirCache: dirCache ?? this.dirCache,
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

  Future<void> _loadDirectory(String path) async {
    try {
      final stat = await fs.stat(path);
      if (!stat.exists || !stat.isDirectory) return;
      final allEntries = await fs.listDir(path);
      final entries = allEntries.where(_matchesFilter).toList()
        ..sort(_compareEntries);
      final cache = Map<String, List<FsDirEntry>>.from(state.dirCache);
      cache[path] = entries;
      emit(state.copyWith(dirCache: cache));
    } catch (_) {
      // Skip directories we can't read
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
