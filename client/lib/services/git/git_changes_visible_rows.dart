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
  }) : change = null,
       isFolder = true;

  const GitChangesVisibleRow.file({
    required this.change,
    required this.depth,
  }) : folderPath = null,
       name = null,
       isFolder = false;

  final String? folderPath;
  final String? name;
  final GitFileChange? change;
  final int depth;
  final bool isFolder;

  @override
  List<Object?> get props => [folderPath, name, change, depth, isFolder];
}

/// Pre-flattened staged + unstaged rows for the changes tree list.
class GitChangesTreeViewData extends Equatable {
  const GitChangesTreeViewData({
    required this.stagedRows,
    required this.unstagedRows,
  });

  final List<GitChangesVisibleRow> stagedRows;
  final List<GitChangesVisibleRow> unstagedRows;

  @override
  List<Object?> get props => [...stagedRows, ...unstagedRows];
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

/// Leading chrome: chevron slot + icon + gap (16px icons).
const double kGitChangesLeadingChromeWidth = 16 + 16 + 6;

/// Trailing stage/unstage actions (two compact buttons).
const double kGitChangesTrailingActionsWidth = 60;

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
    if (row.isFolder) {
      painter.text = TextSpan(text: row.name, style: folderLabelStyle);
      painter.layout();
      final rowWidth =
          row.depth * kGitChangesIndentWidth +
          kGitChangesNodePaddingLeft +
          kGitChangesLeadingChromeWidth +
          kGitChangesNodePaddingRight +
          kGitChangesRowHorizontalPadding * 2 +
          painter.width +
          kGitChangesTrailingActionsWidth;
      maxWidth = math.max(maxWidth, rowWidth);
      continue;
    }

    final label = p.basename(row.change!.path);
    painter.text = TextSpan(text: label, style: fileLabelStyle);
    painter.layout();
    final trailing = row.change!.staged
        ? kGitChangesTrailingBadgeWidth
        : kGitChangesTrailingActionsWidth;
    final rowWidth =
        row.depth * kGitChangesIndentWidth +
        kGitChangesNodePaddingLeft +
        kGitChangesLeadingChromeWidth +
        kGitChangesNodePaddingRight +
        kGitChangesRowHorizontalPadding * 2 +
        painter.width +
        trailing;
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
  final trailing = row.isFolder || !row.change!.staged
      ? kGitChangesTrailingActionsWidth
      : kGitChangesTrailingBadgeWidth;
  return row.depth * 2.0 + units + trailing / 8.0;
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

GitChangesTreeViewData visibleGitChangesTreeViewData({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
}) {
  return GitChangesTreeViewData(
    stagedRows: visibleGitChangesRows(
      changes: staged,
      expandedFolderPaths: expandedFolderPaths,
    ),
    unstagedRows: visibleGitChangesRows(
      changes: unstaged,
      expandedFolderPaths: expandedFolderPaths,
    ),
  );
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

void _walk({
  required _GitChangesFolderNode node,
  required String folderPath,
  required int depth,
  required Set<String> expandedFolderPaths,
  required List<GitChangesVisibleRow> rows,
}) {
  final folderNames = node.subfolders.keys.toList()..sort();
  for (final name in folderNames) {
    final childPath =
        folderPath.isEmpty ? name : p.posix.join(folderPath, name);
    rows.add(
      GitChangesVisibleRow.folder(
        folderPath: childPath,
        name: name,
        depth: depth,
      ),
    );
    if (expandedFolderPaths.contains(childPath)) {
      _walk(
        node: node.subfolders[name]!,
        folderPath: childPath,
        depth: depth + 1,
        expandedFolderPaths: expandedFolderPaths,
        rows: rows,
      );
    }
  }

  final files = node.files.toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  for (final change in files) {
    rows.add(GitChangesVisibleRow.file(change: change, depth: depth));
  }
}
