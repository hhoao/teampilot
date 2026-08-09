import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../../models/git_status.dart';

/// One rendered row in the flattened git changes tree.
class GitChangesVisibleRow extends Equatable {
  const GitChangesVisibleRow.folder({
    required this.folderPath,
    required this.name,
    required this.depth,
    required this.subtreeStagedCount,
    required this.subtreeTotalCount,
  }) : change = null,
       isFolder = true;

  const GitChangesVisibleRow.file({required this.change, required this.depth})
    : folderPath = null,
      name = null,
      subtreeStagedCount = 0,
      subtreeTotalCount = 0,
      isFolder = false;

  final String? folderPath;
  final String? name;
  final GitFileChange? change;
  final int depth;
  final int subtreeStagedCount;
  final int subtreeTotalCount;
  final bool isFolder;

  @override
  List<Object?> get props => [
    folderPath,
    name,
    change,
    depth,
    subtreeStagedCount,
    subtreeTotalCount,
    isFolder,
  ];
}

/// Pre-flattened unified rows for the changes tree list, with staged/total
/// counts so the panel can render tri-state folder checkboxes and badges.
class GitChangesTreeViewData extends Equatable {
  const GitChangesTreeViewData({
    required this.rows,
    required this.stagedCount,
    required this.totalCount,
  });

  final List<GitChangesVisibleRow> rows;
  final int stagedCount;
  final int totalCount;

  bool get allStaged => totalCount > 0 && stagedCount == totalCount;
  bool get noneStaged => stagedCount == 0;

  @override
  List<Object?> get props => [...rows, stagedCount, totalCount];
}

/// Inner content height of a git changes row (excluding outer vertical padding).
const double kGitChangesNodeHeight = 28;

/// Vertical padding around each git changes row in tree view.
const double kGitChangesRowVerticalPadding = 4;

/// Height of a tree row slot (`kGitChangesNodeHeight` + vertical padding).
const double kGitChangesRowExtent =
    kGitChangesNodeHeight + kGitChangesRowVerticalPadding * 2;

/// Matches [GitChangeTile] / [GitChangeFolderTile] indent step.
const double kGitChangesIndentWidth = 16;

/// Outer horizontal inset on each list row in tree view.
const double kGitChangesRowHorizontalPadding = 2;

/// Inner left/right padding on change rows.
const double kGitChangesNodePaddingLeft = 6;
const double kGitChangesNodePaddingRight = 6;

/// Width of the stage checkbox at the leading edge of each row.
const double kGitChangesCheckboxWidth = 18;

/// Single status badge width.
const double kGitChangesTrailingBadgeWidth = 22;

const double kGitChangesContentWidthSlack = 12;

/// Above this row count, only the widest [_kContentWidthCandidates] candidate
/// rows (by a cheap char-width estimate) are actually shaped.
const int _kContentWidthCandidates = 32;

/// Minimum content width so the widest visible tree row fits without truncation.
double gitChangesMinContentWidth({
  required List<GitChangesVisibleRow> rows,
  required TextStyle fileLabelStyle,
  required TextStyle folderLabelStyle,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (rows.isEmpty) return 0;

  final List<GitChangesVisibleRow> measured;
  if (rows.length > _kContentWidthCandidates) {
    measured = [...rows]
      ..sort((a, b) => _rowWidthEstimate(b).compareTo(_rowWidthEstimate(a)));
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
    if (row.isFolder) {
      painter.text = TextSpan(text: row.name, style: folderLabelStyle);
      painter.layout();
      final leading = kGitChangesIndentWidth +
          kGitChangesCheckboxWidth +
          16 +
          6; // chevron + checkbox + folder icon + gap
      final rowWidth =
          row.depth * kGitChangesIndentWidth +
          kGitChangesNodePaddingLeft +
          leading +
          kGitChangesNodePaddingRight +
          kGitChangesRowHorizontalPadding * 2 +
          painter.width;
      maxWidth = math.max(maxWidth, rowWidth);
      continue;
    }

    final label = p.basename(row.change!.path);
    painter.text = TextSpan(text: label, style: fileLabelStyle);
    painter.layout();
    final leading =
        kGitChangesCheckboxWidth + 16 + 6; // checkbox + file icon + gap
    final rowWidth =
        row.depth * kGitChangesIndentWidth +
        kGitChangesNodePaddingLeft +
        leading +
        kGitChangesNodePaddingRight +
        kGitChangesRowHorizontalPadding * 2 +
        painter.width +
        kGitChangesTrailingBadgeWidth;
    maxWidth = math.max(maxWidth, rowWidth);
  }
  return maxWidth.ceilToDouble() + kGitChangesContentWidthSlack;
}

double _rowWidthEstimate(GitChangesVisibleRow row) {
  final label = row.isFolder ? row.name! : p.basename(row.change!.path);
  var units = 0.0;
  for (final rune in label.runes) {
    units += rune >= 0x1100 ? 2.0 : 1.0;
  }
  final extra = row.isFolder ? kGitChangesCheckboxWidth : kGitChangesTrailingBadgeWidth;
  return row.depth * 2.0 + units + extra / 8.0;
}

/// Default expanded folders: every directory prefix of a changed path.
Set<String> gitChangesDefaultExpandedFolders(List<GitFileChange> changes) {
  final paths = <String>{};
  for (final change in changes) {
    var dir = p.posix.dirname(change.path);
    while (dir != '.' && dir.isNotEmpty) {
      paths.add(p.posix.normalize(dir));
      dir = p.posix.dirname(dir);
    }
  }
  return paths;
}

/// Every folder node in the git changes tree (same set as default expansion).
Set<String> gitChangesAllFolderPaths(List<GitFileChange> changes) =>
    gitChangesDefaultExpandedFolders(changes);

GitChangesTreeViewData visibleUnifiedGitChangesTreeView({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
}) {
  final merged = mergeGitChangesByPath(staged: staged, unstaged: unstaged);
  var stagedCount = 0;
  for (final c in merged) {
    if (c.staged) stagedCount++;
  }
  final rows = visibleGitChangesRows(
    changes: merged,
    expandedFolderPaths: expandedFolderPaths,
  );
  return GitChangesTreeViewData(
    rows: rows,
    stagedCount: stagedCount,
    totalCount: merged.length,
  );
}

/// Merges staged + unstaged into one list, deduped by path. When a path
/// appears in both (partial staging), the staged entry wins for kind/badge
/// and `staged` reflects "has staged content".
List<GitFileChange> mergeGitChangesByPath({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
}) {
  final byPath = <String, GitFileChange>{};
  for (final c in unstaged) byPath.putIfAbsent(c.path, () => c);
  for (final c in staged) byPath[c.path] = c;
  return byPath.values.toList();
}

/// Flatten [changes] into folder + file rows for tree view.
List<GitChangesVisibleRow> visibleGitChangesRows({
  required List<GitFileChange> changes,
  required Set<String> expandedFolderPaths,
}) {
  if (changes.isEmpty) return const [];

  final root = _GitChangesFolderNode();
  for (final change in changes) {
    _insertChange(root, change);
  }

  final rows = <GitChangesVisibleRow>[];
  _walk(
    node: root,
    folderPath: '',
    depth: 0,
    expandedFolderPaths: expandedFolderPaths,
    rows: rows,
    emit: true,
  );
  return rows;
}

class _GitChangesFolderNode {
  final Map<String, _GitChangesFolderNode> subfolders = {};
  final List<GitFileChange> files = [];
}

void _insertChange(_GitChangesFolderNode root, GitFileChange change) {
  final normalized = p.posix.normalize(change.path);
  final segments = p.posix.split(normalized);
  if (segments.length == 1) {
    root.files.add(change);
    return;
  }
  var node = root;
  for (var i = 0; i < segments.length - 1; i++) {
    node = node.subfolders.putIfAbsent(segments[i], _GitChangesFolderNode.new);
  }
  node.files.add(change);
}

(int, int) _walk({
  required _GitChangesFolderNode node,
  required String folderPath,
  required int depth,
  required Set<String> expandedFolderPaths,
  required List<GitChangesVisibleRow> rows,
  required bool emit,
}) {
  var total = 0;
  var staged = 0;
  final folderNames = node.subfolders.keys.toList()..sort();
  for (final name in folderNames) {
    final childPath = folderPath.isEmpty ? name : p.posix.join(folderPath, name);
    final childRows = <GitChangesVisibleRow>[];
    final (childTotal, childStaged) = _walk(
      node: node.subfolders[name]!,
      folderPath: childPath,
      depth: depth + 1,
      expandedFolderPaths: expandedFolderPaths,
      rows: childRows,
      emit: emit && expandedFolderPaths.contains(childPath),
    );
    if (emit) {
      rows.add(
        GitChangesVisibleRow.folder(
          folderPath: childPath,
          name: name,
          depth: depth,
          subtreeStagedCount: childStaged,
          subtreeTotalCount: childTotal,
        ),
      );
      rows.addAll(childRows);
    }
    total += childTotal;
    staged += childStaged;
  }
  for (final change in node.files) {
    total++;
    if (change.staged) staged++;
    if (emit) rows.add(GitChangesVisibleRow.file(change: change, depth: depth));
  }
  return (total, staged);
}
