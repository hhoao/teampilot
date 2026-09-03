import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_actions_controller.dart';
import '../../cubits/git_graph_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';
import '../../services/git/git_repo_store.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';
import '../../widgets/app_toast/app_toast.dart';
import 'git_graph_column_header.dart';
import 'git_graph_columns.dart';
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
  /// 不经 InheritedWidget/桥接，直接持有本工作区的 scope cubit：
  /// Bloc 响应式，state 就绪（roots/context 填充）即可渲染，不依赖
  /// “晚插入通知”，也不再受浮动面板子树结构影响。
  WorkspaceToolsScopeRegistry? _registry;

  @override
  void initState() {
    super.initState();
    _listenRegistry(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenRegistry(context);
  }

  void _listenRegistry(BuildContext context) {
    WorkspaceToolsScopeRegistry? registry;
    try {
      registry = context.read<WorkspaceToolsScopeRegistry>();
    } catch (_) {
      return;
    }
    if (identical(registry, _registry)) return;
    _registry?.removeListener(_onRegistryChanged);
    _registry = registry;
    _onRegistryChanged();
    registry.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _registry?.removeListener(_onRegistryChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provided = _providedCubit(context);
    if (provided != null) {
      return BlocProvider.value(
        value: provided,
        child: _PaneBody(workspaceId: widget.workspaceId),
      );
    }
    final scopeCubit = _registry?.peek(widget.workspaceId);
    // 主路径：registry cubit（Bloc 响应式，不依赖 InheritedWidget 晚插入通知）。
    if (scopeCubit != null) {
      return BlocProvider<WorkspaceToolsScopeCubit>.value(
        value: scopeCubit,
        child: BlocBuilder<WorkspaceToolsScopeCubit, WorkspaceToolsScopeState>(
          builder: (context, state) {
            final ctx = _ctxFromState(state);
            if (ctx == null) {
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return BlocProvider.value(
              value: context.read<GitRepoStore>().graphCubitFor(
                widget.repoRoot,
                workContext: ctx,
              ),
              child: _PaneBody(workspaceId: widget.workspaceId),
            );
          },
        ),
      );
    }
    // 工作区 scope 尚未注册；registry 监听在注册完成时触发重建。
    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  RuntimeContext? _ctxFromState(WorkspaceToolsScopeState state) {
    RuntimeContext? ctx;
    for (final slice in state.targetSlices) {
      if (slice.roots.contains(widget.repoRoot)) {
        ctx = slice.tools.context;
        break;
      }
    }
    ctx ??= state.tools?.context;
    return ctx;
  }

  /// 祖先已提供 cubit（surface / 测试宿主）时直接复用，不经过 store。
  static GitGraphCubit? _providedCubit(BuildContext context) {
    try {
      return context.read<GitGraphCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final headerVisible = context.select<LayoutCubit, bool>(
      (cubit) => cubit.state.preferences.gitGraphHeaderVisible,
    );
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
                  GitGraphToolbar(state: state, workspaceId: workspaceId),
                  if (headerVisible)
                    GitGraphColumnHeader(
                      graphWidth: GitGraphColumns.graphWidthFor(maxLane: 0),
                      onHide: () => context
                          .read<LayoutCubit>()
                          .setGitGraphHeaderVisible(false),
                    ),
                  Expanded(
                    child: _GraphList(state: state, workspaceId: workspaceId),
                  ),
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
  const _GraphList({required this.state, required this.workspaceId});

  final GitGraphState state;
  final String workspaceId;

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

    // hash 模式下已加载行全被过滤掉：提示还有更早历史可加载，而非“无提交”。
    if (state.searchMode == GitSearchMode.hash &&
        state.searchQuery.isNotEmpty &&
        rows.isEmpty &&
        state.rows.isNotEmpty) {
      return Center(
        child: Text(
          context.l10n.gitGraphHashSearchEmptyHint,
          textAlign: TextAlign.center,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

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
          return _UncommittedTile(
            dirtyCount: state.dirtyCount,
            workspaceId: widget.workspaceId,
          );
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
          onCommitHashTap: () => unawaited(_copyHash(tileContext, row.hash)),
          onSecondaryTapUp: (details) => unawaited(
            showCommitContextMenu(
              tileContext,
              details.globalPosition,
              row,
              actions,
              state,
              workspaceId: widget.workspaceId,
              repoRoot: state.repoRoot,
            ),
          ),
          onLongPress: () {
            final box = tileContext.findRenderObject();
            final center = box is RenderBox && box.attached
                ? box.localToGlobal(box.size.center(Offset.zero))
                : Offset.zero;
            unawaited(
              showCommitContextMenu(
                tileContext,
                center,
                row,
                actions,
                state,
                workspaceId: widget.workspaceId,
                repoRoot: state.repoRoot,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyHash(BuildContext context, String hash) async {
    await Clipboard.setData(ClipboardData(text: hash));
    if (!context.mounted) return;
    context.showAppToast(context.l10n.gitGraphHashCopied);
  }
}

class _UncommittedTile extends StatelessWidget {
  const _UncommittedTile({required this.dirtyCount, required this.workspaceId});

  final int dirtyCount;
  final String workspaceId;

  /// 打开与 source control 面板一致的未提交 changes diff（整树，working
  /// tree vs HEAD）。
  Future<void> _openChangesDiff(BuildContext context) async {
    final cubit = context.read<GitGraphCubit>();
    await context.read<WorkbenchEditorOpener>().openChangesDiff(
      workspaceId: workspaceId,
      absolutePath: cubit.state.repoRoot,
      title: context.l10n.gitGraphUncommittedChanges,
      loadDiff: ({ignoreWhitespace = false, fullContext = false}) =>
          cubit.workingTreeDiff(
            ignoreWhitespace: ignoreWhitespace,
            fullContext: fullContext,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = cs.primary.withValues(alpha: 0.16);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_openChangesDiff(context)),
        child: Container(
          height: 26,
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            children: [
              SizedBox(
                width: GitGraphColumns.graphWidthFor(maxLane: 0),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: 18,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: GitGraphColumns.afterGraphGap),
              Expanded(
                flex: GitGraphColumns.descriptionFlex,
                child: Row(
                  children: [
                    Text(
                      context.l10n.gitGraphUncommittedChanges,
                      style: TpTextStyles.of(context)
                          .xsColored(cs.onSurfaceVariant)
                          .copyWith(fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$dirtyCount',
                        style: TpTextStyles.of(context).xs,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: GitGraphColumns.metaGap),
              const Flexible(
                flex: GitGraphColumns.dateFlex,
                fit: FlexFit.loose,
                child: SizedBox(width: double.infinity),
              ),
              const SizedBox(width: GitGraphColumns.metaGap),
              const Flexible(
                flex: GitGraphColumns.authorFlex,
                fit: FlexFit.loose,
                child: SizedBox(width: double.infinity),
              ),
              const SizedBox(width: GitGraphColumns.metaGap),
              const SizedBox(width: GitGraphColumns.commitWidth),
            ],
          ),
        ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TpTextStyles.of(context).xsColored(cs.error),
                  ),
                  // 冲突类错误追加处理指引（仅呈现，不改状态）。
                  if (_isConflictError(error))
                    Text(
                      context.l10n.gitGraphConflictHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(context).xsColored(cs.error),
                    ),
                ],
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

  /// 错误信息是否为合并 / 变基冲突（大小写不敏感）。
  static bool _isConflictError(String message) =>
      message.toLowerCase().contains('conflict');
}
