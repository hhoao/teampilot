import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../cubits/git_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import 'git_change_folder_tile.dart';
import 'git_change_tile.dart';

/// Flattened git changes tree (Changes + Unversioned Files sections), mirroring
/// [_FileTreeList] in [FileTreePanel].
class GitChangesTreeList extends StatefulWidget {
  const GitChangesTreeList({
    required this.changesTreeView,
    required this.unversionedTreeView,
    required this.cubit,
    required this.listScrollController,
    required this.horizontalScrollController,
    this.selectedPath,
    this.onSelect = _noopSelect,
    required this.onOpenDiff,
    required this.onConfirmDiscard,
    this.onOpenFile,
    super.key,
  });

  final GitChangesTreeViewData changesTreeView;
  final GitChangesTreeViewData unversionedTreeView;
  final GitCubit cubit;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;

  /// Currently selected change path (highlights the matching file row), or
  /// null when nothing is selected.
  final String? selectedPath;

  /// Called with the change path when a file row is single-clicked.
  final ValueChanged<String> onSelect;
  final ValueChanged<GitFileChange> onOpenDiff;
  final ValueChanged<GitFileChange> onConfirmDiscard;
  final ValueChanged<GitFileChange>? onOpenFile;

  @override
  State<GitChangesTreeList> createState() => _GitChangesTreeListState();
}

class _GitChangesTreeListState extends State<GitChangesTreeList> {
  var _hoverEnabled = true;
  var _activeScrolls = 0;

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _activeScrolls++;
      if (_hoverEnabled) setState(() => _hoverEnabled = false);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _activeScrolls = (_activeScrolls - 1).clamp(0, 1 << 30);
      if (_activeScrolls == 0 && !_hoverEnabled) {
        setState(() => _hoverEnabled = true);
      }
    }
    return false;
  }

  Future<void> _confirmDiscardFolder(String folderPath) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.gitDiscardFolderConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.gitDiscardFolderConfirmBody(folderPath)),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.gitDiscard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.cubit.discardFolder(folderPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fileLabelStyle = TpTextStyles.of(context).sm;
        final folderLabelStyle = TpTextStyles.of(
          context,
        ).smMedium;
        final contentWidth = math.max(
          constraints.maxWidth,
          math.max(
            gitChangesMinContentWidth(
              rows: widget.changesTreeView.rows,
              fileLabelStyle: fileLabelStyle,
              folderLabelStyle: folderLabelStyle,
              textScaler: MediaQuery.textScalerOf(context),
            ),
            widget.unversionedTreeView.rows.isEmpty
                ? 0.0
                : gitChangesMinContentWidth(
                    rows: widget.unversionedTreeView.rows,
                    fileLabelStyle: fileLabelStyle,
                    folderLabelStyle: folderLabelStyle,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
          ),
        );

        return Scrollbar(
          controller: widget.horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: widget.horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: widget.listScrollController,
                thumbVisibility: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: CustomScrollView(
                    scrollCacheExtent: ScrollCacheExtent.pixels(400),
                    controller: widget.listScrollController,
                    slivers: [
                      ..._sectionSlivers(
                        view: widget.changesTreeView,
                        section: GitChangesSection.changes,
                        contentWidth: contentWidth,
                      ),
                      if (widget.unversionedTreeView.totalCount > 0)
                        ..._sectionSlivers(
                          view: widget.unversionedTreeView,
                          section: GitChangesSection.unversioned,
                          contentWidth: contentWidth,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Header + rows slivers for one section. Empty sections render only their
  /// header (the caller skips the whole group when [GitChangesTreeViewData.totalCount] is 0).
  List<Widget> _sectionSlivers({
    required GitChangesTreeViewData view,
    required GitChangesSection section,
    required double contentWidth,
  }) {
    return [
      SliverToBoxAdapter(
        child: _GitChangesRootHeader(
          section: section,
          title: section == GitChangesSection.changes
              ? context.l10n.gitChanges
              : context.l10n.gitUnversionedFiles,
          totalCount: view.totalCount,
          allSelected: view.allSelected,
          noneSelected: view.noneSelected,
          onToggleAll: () {
            if (view.allSelected) {
              unawaited(widget.cubit.selectNone(section));
            } else {
              unawaited(widget.cubit.selectAll(section));
            }
          },
        ),
      ),
      if (view.rows.isNotEmpty)
        SliverFixedExtentList(
          itemExtent: kGitChangesRowExtent,
          delegate: SliverChildBuilderDelegate(
            (context, index) => SizedBox(
              width: contentWidth,
              child: _buildTreeRow(view.rows[index], section),
            ),
            childCount: view.rows.length,
          ),
        ),
    ];
  }

  Widget _buildTreeRow(GitChangesVisibleRow row, GitChangesSection section) {
    final keyPrefix =
        section == GitChangesSection.changes ? 'changes' : 'unversioned';
    if (row.isFolder) {
      return GitChangeFolderTile(
        key: ValueKey('$keyPrefix:folder:${row.folderPath}'),
        folderPath: row.folderPath!,
        name: row.name!,
        depth: row.depth,
        subtreeSelectedCount: row.subtreeSelectedCount,
        subtreeTotalCount: row.subtreeTotalCount,
        cubit: widget.cubit,
        hoverEnabled: _hoverEnabled,
        onStage: () => unawaited(
          widget.cubit.selectFolder(row.folderPath!, section),
        ),
        onUnstage: () => unawaited(
          widget.cubit.deselectFolder(row.folderPath!, section),
        ),
        onDiscardFolder: () => unawaited(_confirmDiscardFolder(row.folderPath!)),
      );
    }

    final change = row.change!;
    final canOpenFile =
        widget.onOpenFile != null && change.kind != GitChangeKind.deleted;
    return GitChangeTile(
      key: ValueKey('$keyPrefix:file:${change.path}'),
      change: change,
      depth: row.depth,
      selected: widget.selectedPath == change.path,
      hoverEnabled: _hoverEnabled,
      onSelect: () => widget.onSelect(change.path),
      onOpenDiff: () => widget.onOpenDiff(change),
      onOpenFile: canOpenFile ? () => widget.onOpenFile!(change) : null,
      onStage: () => unawaited(widget.cubit.selectPath(change.path)),
      onUnstage: () => unawaited(widget.cubit.deselectPath(change.path)),
      onDiscard: () => widget.onConfirmDiscard(change),
    );
  }
}

/// Default [GitChangesTreeList.onSelect] when a caller does not wire selection
/// yet (the panel owns the selected path; unmodified call sites stay valid).
void _noopSelect(String _) {}

/// Top-level section header: a tri-state select-all checkbox plus the change
/// count badge, rendered as the first sliver of each section group.
class _GitChangesRootHeader extends StatelessWidget {
  const _GitChangesRootHeader({
    required this.section,
    required this.title,
    required this.totalCount,
    required this.allSelected,
    required this.noneSelected,
    required this.onToggleAll,
  });

  final GitChangesSection section;
  final String title;
  final int totalCount;
  final bool allSelected;
  final bool noneSelected;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final triState = totalCount == 0
        ? false
        : allSelected
        ? true
        : noneSelected
        ? false
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 2),
      child: Row(
        children: [
          SizedBox(
            width: kGitChangesCheckboxWidth,
            height: kGitChangesCheckboxWidth,
            child: Checkbox(
              key: ValueKey('git-section-toggle-${section.name}'),
              value: triState,
              tristate: true,
              onChanged: (_) => onToggleAll(),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: TpTextStyles.of(
                context,
              ).xsBoldWideColored(cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 2),
          GitChangesCountBadge(count: totalCount),
        ],
      ),
    );
  }
}

class GitChangesCountBadge extends StatelessWidget {
  const GitChangesCountBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TpTextStyles.of(
          context,
        ).xsColored(cs.onSurfaceVariant),
      ),
    );
  }
}
