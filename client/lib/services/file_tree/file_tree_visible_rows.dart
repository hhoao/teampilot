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
    this.isRoot = false,
    this.rootMissing = false,
  });

  final String path;
  final FsDirEntry entry;
  final int depth;
  final bool isEmptyPlaceholder;

  /// True for a workspace-folder header row in a multi-root tree.
  final bool isRoot;

  /// True when this root row points at a directory that no longer exists.
  final bool rootMissing;
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

/// Width reserved for expand/collapse chevron (files keep the slot for alignment).
const double kFileTreeChevronSlotWidth = 18;

/// Gap between chevron and folder/file icon.
const double kFileTreeChevronIconGap = 4;

/// Gap between icon and label.
const double kFileTreeIconLabelGap = 6;

/// Fixed leading chrome before the file label (chevron slot + gaps + icon).
const double kFileTreeLeadingChromeWidth =
    kFileTreeChevronSlotWidth +
    kFileTreeChevronIconGap +
    18 + // [AppIconSizes.mdBase]
    kFileTreeIconLabelGap;

/// Extra width so measured labels do not clip due to font metrics drift.
const double kFileTreeContentWidthSlack = 12;

/// Above this row count, only the widest [_kContentWidthCandidates] candidate
/// rows (by a cheap char-width estimate) are actually shaped. Measuring every
/// row with [TextPainter] on the layout path costs ~120ms of first-time glyph
/// shaping on large trees (it defeats the ListView's laziness); the true widest
/// pixel row is, in practice, always among the longest-estimated rows.
const int _kContentWidthCandidates = 32;

/// Minimum content width so the widest visible row fits without truncation.
double fileTreeMinContentWidth({
  required List<FileTreeVisibleRow> rows,
  required TextStyle labelStyle,
  required TextStyle emptyLabelStyle,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (rows.isEmpty) return 0;

  // Only shape the longest candidates — never the whole (possibly huge) tree.
  final List<FileTreeVisibleRow> measured;
  if (rows.length > _kContentWidthCandidates) {
    measured = [...rows]
      ..sort(
        (a, b) => _rowWidthEstimate(b).compareTo(_rowWidthEstimate(a)),
      );
    measured.length = _kContentWidthCandidates;
  } else {
    measured = rows;
  }

  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  );
  var maxWidth = 0.0;
  for (final row in measured) {
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

/// Cheap, shaping-free width proxy for ranking rows: indent depth plus a
/// per-character cost (CJK/fullwidth glyphs count double). Only used to pick
/// which rows are worth a real [TextPainter] measurement.
double _rowWidthEstimate(FileTreeVisibleRow row) {
  final label = row.isEmptyPlaceholder ? '(empty)' : row.entry.name;
  var units = 0.0;
  for (final rune in label.runes) {
    units += rune >= 0x1100 ? 2.0 : 1.0;
  }
  // Indent is ~16px/level vs ~8px for a narrow glyph → weight depth ~2 units.
  return row.depth * 2.0 + units;
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
  required p.Context Function(String path) pathContextFor,
}) {
  final rows = <FileTreeVisibleRow>[];

  void walk(String dirPath, int depth) {
    final ctx = pathContextFor(dirPath);
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

  if (state.isMultiRoot) {
    // Each workspace folder is a collapsible header; its contents nest one
    // level in. A single folder (below) renders its children at the top level.
    for (final root in state.roots) {
      final ctx = pathContextFor(root.path);
      rows.add(
        FileTreeVisibleRow(
          path: root.path,
          entry: FsDirEntry(name: _rootLabel(ctx, root.path), isDirectory: true),
          depth: 0,
          isRoot: true,
          rootMissing: !root.exists,
        ),
      );
      if (root.exists && state.expandedPaths.contains(root.path)) {
        walk(root.path, 1);
      }
    }
  } else if (state.rootPath.isNotEmpty) {
    walk(state.rootPath, 0);
  }
  return rows;
}

/// Header label for a root row: the folder's basename, falling back to the
/// full path when basename resolution yields nothing.
String _rootLabel(p.Context ctx, String path) {
  final name = ctx.basename(path);
  return name.isEmpty ? path : name;
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
