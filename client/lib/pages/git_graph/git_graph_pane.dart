import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import 'git_graph_detail_pane.dart';
import 'git_graph_menus.dart';
import 'git_graph_row_tile.dart';
import 'git_graph_toolbar.dart';

/// 浮动面板主体。内部：
/// BlocProvider.value(value: store.graphCubitFor(repoRoot, workContext))
/// 由 surface 保证——pane 自身假定祖先已提供 GitGraphCubit。
class GitGraphPane extends StatefulWidget {
  const GitGraphPane({
    super.key,
    required this.workspaceId,
    required this.repoRoot,
  });

  final String workspaceId;
  final String repoRoot;

  @override
  State<GitGraphPane> createState() => _GitGraphPaneState();
}

class _GitGraphPaneState extends State<GitGraphPane> {
  @override
  Widget build(BuildContext context) {
    final provided = _providedCubit(context);
    if (provided != null) {
      return BlocProvider.value(value: provided, child: const _PaneBody());
    }
    final workContext = _resolveWorkContext(context);
    if (workContext == null) return const SizedBox.shrink();
    return BlocProvider(
      create: (_) => context.read<GitRepoStore>().graphCubitFor(
        widget.repoRoot,
        workContext: workContext,
      )..selectCommit(null),
      child: const _PaneBody(),
    );
  }

  /// 祖先已提供 cubit（surface / 测试宿主）时直接复用，不经过 store。
  static GitGraphCubit? _providedCubit(BuildContext context) {
    try {
      return context.read<GitGraphCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 仓库根所属后端上下文：优先命中包含 repoRoot 的 target 切片，
  /// 回退到活动工具平面；两者皆缺（无 workspace 环境）时面板收缩。
  RuntimeContext? _resolveWorkContext(BuildContext context) {
    final scope = WorkspaceToolsScope.maybeOf(context);
    for (final slice in scope?.targetSlices ?? const <WorkspaceTargetSlice>[]) {
      if (slice.roots.contains(widget.repoRoot)) return slice.tools.context;
    }
    return scope?.tools?.context;
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GitGraphCubit, GitGraphState>(
      builder: (context, state) {
        if (!state.gitAvailable && !state.isRefreshing) {
          return _NotARepositoryHint(state: state);
        }
        final cubit = context.read<GitGraphCubit>();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  GitGraphToolbar(state: state),
                  Expanded(child: _GraphList(state: state)),
                  if (state.errorMessage != null ||
                      state.currentBranch.isNotEmpty)
                    _StatusBar(state: state),
                ],
              ),
            ),
            // 详情栏：选中提交后展开固定宽度右栏；未选中时收起，避免挤压图区。
            if (state.selectedHash != null) ...[
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              SizedBox(
                width: 380,
                child: GitGraphDetailPane(
                  onBack: () => cubit.selectCommit(null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _NotARepositoryHint extends StatelessWidget {
  const _NotARepositoryHint({required this.state});

  final GitGraphState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined, size: 28, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            state.repoRoot.isEmpty ? '' : context.l10n.gitGraphNotARepository,
            style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _GraphList extends StatefulWidget {
  const _GraphList({required this.state});

  final GitGraphState state;

  @override
  State<_GraphList> createState() => _GraphListState();
}

class _GraphListState extends State<_GraphList> {
  static const double _loadMoreThreshold = 200;

  final ScrollController _controller = ScrollController();

  late final GitGraphCubit _cubit = context.read<GitGraphCubit>();

  // 挂载期间向 cubit 登记占用，避免 GitRepoStore 的 LRU 淘汰关闭在用面板。
  void _occupy() {}

  @override
  void initState() {
    super.initState();
    _cubit.addListener(_occupy);
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _cubit.removeListener(_occupy);
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// 距底部不足阈值时预取下一页（cubit 内部有 in-flight 去重）。
  void _onScroll() {
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      context.read<GitGraphCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rows = state.visibleRows;
    final hasDirtyRow = state.dirtyCount > 0;
    final itemCount =
        (hasDirtyRow ? 1 : 0) + rows.length + (state.hasMore ? 1 : 0);

    if (itemCount == 0) {
      return Center(
        child: Text(
          context.l10n.gitGraphNoCommits,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: _controller,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasDirtyRow && index == 0) {
          return _UncommittedTile(dirtyCount: state.dirtyCount);
        }
        final rowIndex = index - (hasDirtyRow ? 1 : 0);
        if (rowIndex < rows.length) {
          final row = rows[rowIndex];
          if (row is GitCommitRow) return _commitTile(context, row, state);
          return GitGraphSpacerTile(
            key: ValueKey('git-graph-spacer-$rowIndex'),
            row: row,
          );
        }
        return _LoadMoreTile(isLoading: state.isLoadingMore);
      },
    );
  }

  Widget _commitTile(
    BuildContext context,
    GitCommitRow row,
    GitGraphState state,
  ) {
    final cubit = context.read<GitGraphCubit>();
    final actions = GitGraphActionsController(cubit: cubit);
    return Builder(
      builder: (tileContext) => BlocProvider.value(
        value: cubit,
        child: GitGraphRowTile(
          key: ValueKey('git-graph-row-${row.hash}'),
          row: row,
          selected: state.selectedHash == row.hash,
          onTap: () => cubit.selectCommit(row.hash),
          onSecondaryTapUp: (details) => unawaited(
            showCommitContextMenu(
              tileContext,
              details.globalPosition,
              row,
              actions,
              state,
            ),
          ),
          onLongPress: () {
            final box = tileContext.findRenderObject();
            final center = box is RenderBox && box.attached
                ? box.localToGlobal(box.size.center(Offset.zero))
                : Offset.zero;
            unawaited(
              showCommitContextMenu(tileContext, center, row, actions, state),
            );
          },
        ),
      ),
    );
  }
}

class _UncommittedTile extends StatelessWidget {
  const _UncommittedTile({required this.dirtyCount});

  final int dirtyCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = cs.primary.withValues(alpha: 0.16);
    return Container(
      height: 26,
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Icon(Icons.edit_note_rounded, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 6),
          Text(
            context.l10n.gitGraphUncommittedChanges,
            style: TpTextStyles.of(context)
                .xsColored(cs.onSurfaceVariant)
                .copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$dirtyCount', style: TpTextStyles.of(context).xs),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.gitGraphLoadingMore,
                  style: TpTextStyles.of(context).xs,
                ),
              ],
            )
          : TpHover(
              onTap: () => context.read<GitGraphCubit>().loadMore(),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              borderRadius: BorderRadius.circular(6),
              child: Text(
                l10n.gitGraphLoadMore,
                style: TpTextStyles.of(context).xs,
              ),
            ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final GitGraphState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final error = state.errorMessage;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      color: error != null ? cs.errorContainer.withValues(alpha: 0.5) : null,
      child: Row(
        children: [
          if (error != null) ...[
            Icon(Icons.error_outline_rounded, size: 13, color: cs.error),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(context).xsColored(cs.error),
              ),
            ),
          ] else ...[
            Icon(
              Icons.call_split_rounded,
              size: 12,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                state.currentBranch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
              ),
            ),
            if (state.ahead > 0)
              Text(
                '↑${state.ahead}',
                style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
              ),
            if (state.behind > 0) ...[
              const SizedBox(width: 6),
              Text(
                '↓${state.behind}',
                style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
