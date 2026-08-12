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
    required this.subtreeSelectedCount,
    required this.subtreeTotalCount,
  }) : change = null,
       isFolder = true;

  const GitChangesVisibleRow.file({required this.change, required this.depth})
    : folderPath = null,
      name = null,
      subtreeSelectedCount = 0,
      subtreeTotalCount = 0,
      isFolder = false;

  final String? folderPath;
  final String? name;
  final GitFileChange? change;
  final int depth;
  final int subtreeSelectedCount;
  final int subtreeTotalCount;
  final bool isFolder;

  @override
  List<Object?> get props => [
    folderPath,
    name,
    change,
    depth,
    subtreeSelectedCount,
    subtreeTotalCount,
    isFolder,
  ];
}

/// Pre-flattened unified rows for the changes tree list, with selected/total
/// counts so the panel can render tri-state folder checkboxes and badges.
/// `selectedCount` / `allSelected` / `noneSelected` mean "selected for the
/// next commit" (the checkbox state), not the git index.
class GitChangesTreeViewData extends Equatable {
  const GitChangesTreeViewData({
    required this.rows,
    required this.selectedCount,
    required this.totalCount,
  });

  final List<GitChangesVisibleRow> rows;
  final int selectedCount;
  final int totalCount;

  bool get allSelected => totalCount > 0 && selectedCount == totalCount;
  bool get noneSelected => selectedCount == 0;

  @override
  List<Object?> get props => [...rows, selectedCount, totalCount];
}

/// Inner content height of a git changes row (excluding outer vertical padding).
const double kGitChangesNodeHeight = 28;

/// Vertical padding around each git changes row in tree view.
const double kGitChangesRowVerticalPadding = 4;

/// Height of a tree row slot (`kGitChangesNodeHeight` + vertical padding).
const double kGitChangesRowExtent =
    kGitChangesNodeHeight + kGitChangesRowVerticalPadding * 2;

/// Folder indent step per tree level: the chevron column (18) plus the
/// checkbox's left padding (2). Files indent by this plus a chevron column.
/// The extra 2px keeps a child folder's chevron aligned with its parent's
/// checkbox box while opening a 2px gap between parent and child checkbox
/// boxes (a child box starts at its parent box's right edge + 2).
const double kGitChangesIndentWidth = 20;

/// Outer horizontal inset on each list row in tree view.
const double kGitChangesRowHorizontalPadding = 2;

/// Inner left/right padding on change rows.
const double kGitChangesNodePaddingLeft = 6;
const double kGitChangesNodePaddingRight = 6;

/// Width of the stage checkbox at the leading edge of each row.
const double kGitChangesCheckboxWidth = 18;

/// Horizontal padding inside the stage-checkbox column, so the box doesn't sit
/// flush against the chevron (or the row edge) on the left and the file/folder
/// icon on the right. The box keeps its natural [kGitChangesCheckboxWidth]
/// size; the extra room widens the column, not the box.
const double kGitChangesCheckboxHPadding = 2;

/// Width of the stage-checkbox column: the [kGitChangesCheckboxWidth] box plus
/// [kGitChangesCheckboxHPadding] on each side. The box keeps its natural size;
/// [kGitChangesIndentWidth] absorbs the left padding so a child folder's
/// chevron stays aligned with its parent's checkbox box.
const double kGitChangesCheckboxColumnWidth =
    kGitChangesCheckboxWidth + kGitChangesCheckboxHPadding * 2;

/// Width of the folder chevron column; equal to the checkbox width so a child
/// file's checkbox left edge lands exactly on its parent folder's checkbox
/// right edge.
const double kGitChangesChevronWidth = kGitChangesCheckboxWidth;

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
      final leading = kGitChangesChevronWidth +
          kGitChangesCheckboxColumnWidth +
          16 +
          6; // chevron + checkbox column + folder icon + gap
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
        kGitChangesCheckboxColumnWidth + 16 + 6; // checkbox column + file icon + gap
    final rowWidth =
        row.depth * kGitChangesIndentWidth +
        kGitChangesChevronWidth +
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

/// Which change group a source-control section shows.
enum GitChangesSection { changes, unversioned }

/// The two source-control sections: tracked changes and unversioned files.
class GitChangesSections extends Equatable {
  const GitChangesSections({required this.changes, required this.unversioned});

  final GitChangesTreeViewData changes;
  final GitChangesTreeViewData unversioned;

  @override
  List<Object?> get props => [changes, unversioned];
}

/// Builds both source-control sections from a status snapshot.
GitChangesSections visibleGitChangesSections({
  required List<GitFileChange> staged,
  required List<GitFileChange> unstaged,
  required Set<String> expandedFolderPaths,
  required Set<String> selectedPaths,
}) {
  final merged = mergeGitChangesByPath(staged: staged, unstaged: unstaged);
  final changes = <GitFileChange>[];
  final unversioned = <GitFileChange>[];
  for (final c in merged) {
    (c.kind == GitChangeKind.untracked ? unversioned : changes).add(c);
  }
  return GitChangesSections(
    changes: visibleGitChangesTreeView(
      changes: changes,
      expandedFolderPaths: expandedFolderPaths,
      selectedPaths: selectedPaths,
    ),
    unversioned: visibleGitChangesTreeView(
      changes: unversioned,
      expandedFolderPaths: expandedFolderPaths,
      selectedPaths: selectedPaths,
    ),
  );
}

/// One section's tree: projects the checkbox state from [selectedPaths] (the
/// UI "include in next commit" selection, not the git index).
GitChangesTreeViewData visibleGitChangesTreeView({
  required List<GitFileChange> changes,
  required Set<String> expandedFolderPaths,
  required Set<String> selectedPaths,
}) {
  final projected = <GitFileChange>[
    for (final c in changes) c.copyWith(staged: selectedPaths.contains(c.path)),
  ];
  var selectedCount = 0;
  for (final c in projected) {
    if (c.staged) selectedCount++;
  }
  final rows = visibleGitChangesRows(
    changes: projected,
    expandedFolderPaths: expandedFolderPaths,
  );
  return GitChangesTreeViewData(
    rows: rows,
    selectedCount: selectedCount,
    totalCount: changes.length,
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
  for (final c in unstaged) {
    byPath.putIfAbsent(c.path, () => c);
  }
  for (final c in staged) {
    byPath[c.path] = c;
  }
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
  var selected = 0;
  final folderNames = node.subfolders.keys.toList()..sort();
  for (final name in folderNames) {
    final childPath = folderPath.isEmpty ? name : p.posix.join(folderPath, name);
    final childRows = <GitChangesVisibleRow>[];
    final (childTotal, childSelected) = _walk(
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
          subtreeSelectedCount: childSelected,
          subtreeTotalCount: childTotal,
        ),
      );
      rows.addAll(childRows);
    }
    total += childTotal;
    selected += childSelected;
  }
  final files = node.files.toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  for (final change in files) {
    total++;
    if (change.staged) selected++;
    if (emit) rows.add(GitChangesVisibleRow.file(change: change, depth: depth));
  }
  return (total, selected);
}
