import 'dart:math' as math;

import 'package:flutter/painting.dart';
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

/// Inner content height of a tree row (excluding outer vertical padding).
const double kFileTreeNodeHeight = 28;

/// Vertical padding around each tree row in the list.
const double kFileTreeRowVerticalPadding = 4;

/// Height of a tree row slot in [ListView] (`kFileTreeNodeHeight` + vertical padding).
const double kFileTreeRowExtent =
    kFileTreeNodeHeight + kFileTreeRowVerticalPadding * 2;

/// Matches [FileTreeNode] indent step.
const double kFileTreeIndentWidth = 16;

/// Outer horizontal inset on each list row in the file tree panel.
const double kFileTreeRowHorizontalPadding = 2;

/// Inner left/right padding on [FileTreeNode].
const double kFileTreeNodePaddingLeft = 4;
const double kFileTreeNodePaddingRight = 8;

/// Fixed leading chrome before the file label (chevron slot + icon + gap).
const double kFileTreeLeadingChromeWidth =
    18 + 22 + 6; // chevron slot + AppIconSizes.md + gap

/// Extra width so measured labels do not clip due to font metrics drift.
const double kFileTreeContentWidthSlack = 12;

/// Minimum content width so the widest visible row fits without truncation.
double fileTreeMinContentWidth({
  required List<FileTreeVisibleRow> rows,
  required TextStyle labelStyle,
  required TextStyle emptyLabelStyle,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (rows.isEmpty) return 0;

  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  );
  var maxWidth = 0.0;
  for (final row in rows) {
    final label = row.isEmptyPlaceholder ? '(empty)' : row.entry.name;
    final baseStyle = row.isEmptyPlaceholder ? emptyLabelStyle : labelStyle;
    var textWidth = _measureTextWidth(
      painter: painter,
      label: label,
      style: baseStyle,
    );
    if (!row.isEmptyPlaceholder) {
      textWidth = math.max(
        textWidth,
        _measureTextWidth(
          painter: painter,
          label: label,
          style: baseStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }
    final rowWidth =
        row.depth * kFileTreeIndentWidth +
        kFileTreeNodePaddingLeft +
        kFileTreeLeadingChromeWidth +
        kFileTreeNodePaddingRight +
        kFileTreeRowHorizontalPadding * 2 +
        textWidth;
    maxWidth = math.max(maxWidth, rowWidth);
  }
  return maxWidth.ceilToDouble() + kFileTreeContentWidthSlack;
}

double _measureTextWidth({
  required TextPainter painter,
  required String label,
  required TextStyle style,
}) {
  painter.text = TextSpan(text: label, style: style);
  painter.layout();
  return painter.width;
}

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
