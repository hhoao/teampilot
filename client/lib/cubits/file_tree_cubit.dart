import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

class FileTreeState {
  const FileTreeState({
    this.rootPath = '',
    this.expandedPaths = const {},
    this.filterText = '',
    this.showHiddenFiles = false,
    this.dirCache = const {},
  });

  final String rootPath;
  final Set<String> expandedPaths;
  final String filterText;
  final bool showHiddenFiles;
  final Map<String, List<FileSystemEntity>> dirCache;

  FileTreeState copyWith({
    String? rootPath,
    Set<String>? expandedPaths,
    String? filterText,
    bool? showHiddenFiles,
    Map<String, List<FileSystemEntity>>? dirCache,
  }) {
    return FileTreeState(
      rootPath: rootPath ?? this.rootPath,
      expandedPaths: expandedPaths ?? this.expandedPaths,
      filterText: filterText ?? this.filterText,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      dirCache: dirCache ?? this.dirCache,
    );
  }
}

class FileTreeCubit extends Cubit<FileTreeState> {
  FileTreeCubit() : super(const FileTreeState());

  void setRoot(String path) {
    if (path == state.rootPath) return;
    emit(FileTreeState(rootPath: path));
    _loadDirectory(path);
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
    final cache = Map<String, List<FileSystemEntity>>.from(state.dirCache);
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
    final cache = Map<String, List<FileSystemEntity>>.from(state.dirCache);
    cache.clear();
    emit(state.copyWith(dirCache: cache));
    if (state.rootPath.isNotEmpty) {
      _loadDirectory(state.rootPath);
    }
    for (final p in state.expandedPaths) {
      _loadDirectory(p);
    }
  }

  void _loadDirectory(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      final entries = dir
          .listSync()
          .where((e) => _matchesFilter(e))
          .toList()
        ..sort(_compareEntries);
      final cache = Map<String, List<FileSystemEntity>>.from(state.dirCache);
      cache[path] = entries;
      emit(state.copyWith(dirCache: cache));
    } catch (_) {
      // Skip directories we can't read
    }
  }

  List<FileSystemEntity> entriesFor(String path) {
    return state.dirCache[path] ?? [];
  }

  bool _matchesFilter(FileSystemEntity entity) {
    final name = _entityName(entity);
    if (!state.showHiddenFiles && name.startsWith('.')) return false;
    if (state.filterText.isNotEmpty &&
        !name.toLowerCase().contains(state.filterText.toLowerCase())) {
      return false;
    }
    return true;
  }

  static int _compareEntries(FileSystemEntity a, FileSystemEntity b) {
    final aIsDir = a is Directory;
    final bIsDir = b is Directory;
    if (aIsDir && !bIsDir) return -1;
    if (!aIsDir && bIsDir) return 1;
    return _entityName(a)
        .toLowerCase()
        .compareTo(_entityName(b).toLowerCase());
  }

  static String _entityName(FileSystemEntity entity) {
    return entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
  }
}
