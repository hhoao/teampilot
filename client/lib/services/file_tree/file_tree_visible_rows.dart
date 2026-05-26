import 'package:path/path.dart' as p;

import '../../cubits/file_tree_cubit.dart';
import '../io/filesystem.dart';

/// One rendered row in the flattened file tree list.
class FileTreeVisibleRow {
  const FileTreeVisibleRow({
    required this.path,
    required this.entry,
    required this.depth,
    this.isEmptyPlaceholder = false,
  });

  final String path;
  final FsDirEntry entry;
  final int depth;
  final bool isEmptyPlaceholder;
}

/// Height of a tree row (`FileTreeNode` 28px + vertical margin 2px).
const double kFileTreeRowExtent = 30;

bool fileTreePathsEqual(p.Context ctx, String a, String b) {
  final left = ctx.normalize(a);
  final right = ctx.normalize(b);
  if (ctx.equals(left, right)) return true;
  return left.toLowerCase() == right.toLowerCase();
}

/// DFS of expanded directories matching on-screen tree order.
List<FileTreeVisibleRow> visibleFileTreeRows({
  required FileTreeState state,
  required p.Context pathContext,
}) {
  final ctx = pathContext;
  final rows = <FileTreeVisibleRow>[];

  void walk(String dirPath, int depth) {
    final entries = state.dirCache[dirPath] ?? [];
    if (entries.isEmpty) {
      if (depth > 0) {
        rows.add(
          FileTreeVisibleRow(
            path: dirPath,
            entry: const FsDirEntry(name: '(empty)', isDirectory: false),
            depth: depth + 1,
            isEmptyPlaceholder: true,
          ),
        );
      }
      return;
    }
    for (final entry in entries) {
      final childPath = ctx.join(dirPath, entry.name);
      rows.add(
        FileTreeVisibleRow(path: childPath, entry: entry, depth: depth),
      );
      if (entry.isDirectory && state.expandedPaths.contains(childPath)) {
        walk(childPath, depth + 1);
      }
    }
  }

  if (state.rootPath.isNotEmpty) {
    walk(state.rootPath, 0);
  }
  return rows;
}

/// Index in [visibleFileTreeRows] for a file path, or null if not visible.
int? visibleRowIndexForPath(
  List<FileTreeVisibleRow> rows,
  String filePath,
  p.Context pathContext,
) {
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.isEmptyPlaceholder || row.entry.isDirectory) continue;
    if (fileTreePathsEqual(pathContext, row.path, filePath)) {
      return i;
    }
  }
  return null;
}
