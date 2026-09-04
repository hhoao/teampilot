import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';

import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../widgets/file_icon_widget.dart';
import '../../widgets/git/git_changes_tree_list.dart' show GitChangesCountBadge;

/// Read-only changed-file tree for the Git Compare pane.
///
/// Reuses the source-control row geometry and flattening
/// ([visibleGitChangesRows]) but drops the stage checkbox, discard actions and
/// the Changes / Unversioned split: compare shows one section where untracked
/// entries just carry their `?` badge.
class GitCompareFileTree extends StatelessWidget {
  const GitCompareFileTree({
    super.key,
    required this.rows,
    required this.expandedFolderPaths,
    required this.selectedPath,
    required this.onToggleFolder,
    required this.onOpenFile,
  });

  final List<GitChangesVisibleRow> rows;
  final Set<String> expandedFolderPaths;
  final String? selectedPath;
  final ValueChanged<String> onToggleFolder;
  final ValueChanged<GitFileChange> onOpenFile;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemExtent: kGitChangesRowExtent,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isFolder) {
          final folderPath = row.folderPath!;
          return _FolderRow(
            key: ValueKey('git-compare-folder:$folderPath'),
            name: row.name!,
            depth: row.depth,
            fileCount: row.subtreeTotalCount,
            expanded: expandedFolderPaths.contains(folderPath),
            onTap: () => onToggleFolder(folderPath),
          );
        }
        final change = row.change!;
        return _FileRow(
          key: ValueKey('git-compare-file:${change.path}'),
          change: change,
          depth: row.depth,
          selected: selectedPath == change.path,
          onTap: () => onOpenFile(change),
        );
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    super.key,
    required this.name,
    required this.depth,
    required this.fileCount,
    required this.expanded,
    required this.onTap,
  });

  final String name;
  final int depth;
  final int fileCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: TpHover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          depth * kGitChangesIndentWidth +
              kGitChangesNodePaddingLeft +
              kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
          kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
        ),
        child: SizedBox(
          height: kGitChangesNodeHeight,
          child: Row(
            children: [
              SizedBox(
                width: kGitChangesChevronWidth,
                height: 16,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedRotation(
                    turns: expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
              GitChangesCountBadge(count: fileCount),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    super.key,
    required this.change,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final GitFileChange change;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  Color _badgeColor(ColorScheme cs) => switch (change.kind) {
    GitChangeKind.added => const Color(0xFF2EA043),
    GitChangeKind.untracked => const Color(0xFF2EA043),
    GitChangeKind.deleted => cs.error,
    GitChangeKind.conflicted => cs.error,
    GitChangeKind.renamed => cs.primary,
    GitChangeKind.modified => const Color(0xFFB58900),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = p.basename(change.path);
    return RepaintBoundary(
      child: TpHover(
        onTap: onTap,
        backgroundColor: selected ? cs.secondaryContainer : null,
        borderRadius: BorderRadius.circular(6),
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.fromLTRB(
          depth * kGitChangesIndentWidth +
              kGitChangesChevronWidth +
              kGitChangesNodePaddingLeft +
              kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
          kGitChangesNodePaddingRight + kGitChangesRowHorizontalPadding,
          kGitChangesRowVerticalPadding,
        ),
        child: SizedBox(
          height: kGitChangesNodeHeight,
          child: Row(
            children: [
              FileIconWidget(fileName: name),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).md,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: kGitChangesTrailingBadgeWidth,
                child: Text(
                  change.badge,
                  textAlign: TextAlign.center,
                  style: TpTextStyles.of(context).smBoldColored(_badgeColor(cs)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
