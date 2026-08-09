import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../cubits/git_cubit.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import 'package:shared_ui/shared_ui.dart';
import 'git_change_folder_tile.dart';
import 'git_change_tile.dart';

/// Flattened git changes tree (staged + unstaged sections), mirroring
/// [_FileTreeList] in [FileTreePanel].
class GitChangesTreeList extends StatefulWidget {
  const GitChangesTreeList({
    required this.treeView,
    required this.cubit,
    required this.listScrollController,
    required this.horizontalScrollController,
    required this.onOpenDiff,
    required this.onConfirmDiscard,
    this.onOpenFile,
    super.key,
  });

  final GitChangesTreeViewData treeView;
  final GitCubit cubit;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
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
          gitChangesMinContentWidth(
            rows: widget.treeView.rows,
            fileLabelStyle: fileLabelStyle,
            folderLabelStyle: folderLabelStyle,
            textScaler: MediaQuery.textScalerOf(context),
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
                      if (widget.treeView.rows.isNotEmpty)
                        SliverFixedExtentList(
                          itemExtent: kGitChangesRowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => SizedBox(
                              width: contentWidth,
                              child: _buildTreeRow(widget.treeView.rows[index]),
                            ),
                            childCount: widget.treeView.rows.length,
                          ),
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

  Widget _buildTreeRow(GitChangesVisibleRow row) {
    if (row.isFolder) {
      return GitChangeFolderTile(
        key: ValueKey('folder:${row.folderPath}'),
        folderPath: row.folderPath!,
        name: row.name!,
        depth: row.depth,
        cubit: widget.cubit,
        hoverEnabled: _hoverEnabled,
        onStage: () => unawaited(widget.cubit.stageFolder(row.folderPath!)),
        onUnstage: () => unawaited(widget.cubit.unstageFolder(row.folderPath!)),
      );
    }

    final change = row.change!;
    final canOpenFile =
        widget.onOpenFile != null && change.kind != GitChangeKind.deleted;
    return GitChangeTile(
      key: ValueKey('file:${change.path}'),
      change: change,
      depth: row.depth,
      selected: false,
      hoverEnabled: _hoverEnabled,
      onSelect: () => widget.onOpenDiff(change),
      onOpenDiff: () => widget.onOpenDiff(change),
      onOpenFile: canOpenFile ? () => widget.onOpenFile!(change) : null,
      onStage: () => unawaited(widget.cubit.stage(change)),
      onUnstage: () => unawaited(widget.cubit.unstage(change)),
      onDiscard: () => widget.onConfirmDiscard(change),
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
