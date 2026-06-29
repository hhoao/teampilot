import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../cubits/git_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
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
    super.key,
  });

  final GitChangesTreeViewData treeView;
  final GitCubit cubit;
  final ScrollController listScrollController;
  final ScrollController horizontalScrollController;
  final ValueChanged<GitFileChange> onOpenDiff;
  final ValueChanged<GitFileChange> onConfirmDiscard;

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
    final l10n = context.l10n;
    final stagedRows = widget.treeView.stagedRows;
    final unstagedRows = widget.treeView.unstagedRows;
    final stagedCount = widget.cubit.state.status.staged.length;
    final unstagedCount = widget.cubit.state.status.unstaged.length;
    final allRows = [...stagedRows, ...unstagedRows];

    return LayoutBuilder(
      builder: (context, constraints) {
        final fileLabelStyle = AppTextStyles.of(context).bodySmall;
        final folderLabelStyle = AppTextStyles.of(
          context,
        ).bodySmall.copyWith(fontWeight: FontWeight.w500);
        final contentWidth = math.max(
          constraints.maxWidth,
          gitChangesMinContentWidth(
            rows: allRows,
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
                      if (stagedRows.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: GitChangesSectionHeader(
                            title: l10n.gitStagedChanges,
                            count: stagedCount,
                            action: AppIconButton(
                              icon: Icons.remove,
                              compact: true,
                              size: AppIconButton.kCompactSize,
                              tooltip: l10n.gitUnstageAll,
                              onTap: () => unawaited(widget.cubit.unstageAll()),
                            ),
                          ),
                        ),
                        SliverFixedExtentList(
                          itemExtent: kGitChangesRowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => SizedBox(
                              width: contentWidth,
                              child: _buildTreeRow(
                                row: stagedRows[index],
                                staged: true,
                              ),
                            ),
                            childCount: stagedRows.length,
                          ),
                        ),
                      ],
                      if (unstagedRows.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: GitChangesSectionHeader(
                            title: l10n.gitChanges,
                            count: unstagedCount,
                            action: AppIconButton(
                              icon: Icons.add,
                              compact: true,
                              size: AppIconButton.kCompactSize,
                              tooltip: l10n.gitStageAll,
                              onTap: () => unawaited(widget.cubit.stageAll()),
                            ),
                          ),
                        ),
                        SliverFixedExtentList(
                          itemExtent: kGitChangesRowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => SizedBox(
                              width: contentWidth,
                              child: _buildTreeRow(
                                row: unstagedRows[index],
                                staged: false,
                              ),
                            ),
                            childCount: unstagedRows.length,
                          ),
                        ),
                      ],
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

  Widget _buildTreeRow({
    required GitChangesVisibleRow row,
    required bool staged,
  }) {
    if (row.isFolder) {
      return GitChangeFolderTile(
        key: ValueKey('folder:${row.folderPath}'),
        folderPath: row.folderPath!,
        name: row.name!,
        depth: row.depth,
        cubit: widget.cubit,
        hoverEnabled: _hoverEnabled,
        onStage: staged
            ? null
            : () => unawaited(widget.cubit.stageFolder(row.folderPath!)),
        onUnstage: staged
            ? () => unawaited(widget.cubit.unstageFolder(row.folderPath!))
            : null,
      );
    }

    final change = row.change!;
    return GitChangeTile(
      key: ValueKey('${staged ? 'staged' : 'unstaged'}:${change.path}'),
      change: change,
      depth: row.depth,
      hoverEnabled: _hoverEnabled,
      onOpenDiff: () => widget.onOpenDiff(change),
      onStage: staged ? () {} : () => unawaited(widget.cubit.stage(change)),
      onUnstage: staged ? () => unawaited(widget.cubit.unstage(change)) : () {},
      onDiscard: staged ? () {} : () => widget.onConfirmDiscard(change),
    );
  }
}

class GitChangesSectionHeader extends StatelessWidget {
  const GitChangesSectionHeader({
    required this.title,
    required this.count,
    required this.action,
    super.key,
  });

  final String title;
  final int count;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.of(
                context,
              ).toolPanelTitleColored(cs.onSurfaceVariant),
            ),
          ),
          action,
          const SizedBox(width: 2),
          GitChangesCountBadge(count: count),
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
        style: AppTextStyles.of(
          context,
        ).caption.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}
