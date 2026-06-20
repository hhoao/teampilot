import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/git_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../models/ai_feature_setting.dart';
import '../../services/ai/ai_feature_setting_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../services/io/workspace_fs_watcher.dart';
import '../../theme/app_text_styles.dart';
import '../app_dialog.dart';
import '../app_icon_button.dart';
import 'git_branch_menu.dart';
import 'git_change_folder_tile.dart';
import 'git_change_tile.dart';
import 'git_diff_view.dart';

/// VSCode-style "Source Control" panel for the editor workbench left rail.
///
/// Self-contained like `_FileTreePanel`: builds its own [GitCubit] and tracks
/// the active session cwd via [cwd]. Desktop-local git only.
class GitSourceControlPanel extends StatefulWidget {
  const GitSourceControlPanel({
    required this.cwd,
    this.isActive = false,
    this.watcher,
    super.key,
  });

  final String cwd;

  /// When true, the panel auto-refreshes git status. The caller sets this when
  /// this tool tab is the currently selected tab in the right-tools panel.
  final bool isActive;

  /// Shared workspace watcher. When present and supported, status refreshes
  /// live on disk changes; otherwise the panel falls back to periodic polling.
  final WorkspaceFsWatcher? watcher;

  @override
  State<GitSourceControlPanel> createState() => _GitSourceControlPanelState();
}

class _GitSourceControlPanelState extends State<GitSourceControlPanel> {
  final _cubit = GitCubit();
  final _commitController = TextEditingController();
  final _changesScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  static const _refreshInterval = Duration(seconds: 15);
  Timer? _refreshTimer;
  StreamSubscription<void>? _watchSub;

  /// True when live disk watching can drive refresh, so the polling timer is
  /// unnecessary. Falls back to polling on backends without watch support.
  bool get _watchDriven => widget.watcher?.isSupported ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_cubit.setRepoRoot(widget.cwd));
    _subscribeWatcher();
    if (widget.isActive) {
      _startAutoRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant GitSourceControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd) {
      unawaited(_cubit.setRepoRoot(widget.cwd));
    }
    if (!identical(widget.watcher, oldWidget.watcher)) {
      _subscribeWatcher();
    }
    if (widget.isActive && !oldWidget.isActive) {
      _cubit.refresh();
      _startAutoRefresh();
    } else if (!widget.isActive && oldWidget.isActive) {
      _cancelAutoRefresh();
    }
  }

  void _subscribeWatcher() {
    _watchSub?.cancel();
    _watchSub = widget.watcher?.onChanged.listen((_) {
      // Only refresh while this tab is visible; switching to it refreshes via
      // didUpdateWidget, so background git calls aren't needed.
      if (widget.isActive) _cubit.refresh();
    });
    // A live watch makes the polling timer redundant.
    if (_watchDriven) _cancelAutoRefresh();
  }

  void _startAutoRefresh() {
    if (_watchDriven) return;
    _cancelAutoRefresh();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      _cubit.refresh();
    });
  }

  void _cancelAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    _cancelAutoRefresh();
    _commitController.dispose();
    _changesScrollController.dispose();
    _horizontalScrollController.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _openDiff(GitFileChange change) async {
    final editor = context.read<EditorCubit>();
    final diff = await _cubit.diff(change);
    if (!mounted || diff == null) return;
    final absolutePath = p.join(_cubit.state.repoRoot, change.path);
    await GitDiffDialog.show(
      context,
      title: change.path,
      diff: diff,
      reloadDiff: (ignoreWhitespace, fullContext) => _cubit.diff(
        change,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      ),
      // The dialog closes itself (via its own context); we just open the file.
      onOpenSource: () => unawaited(editor.openFile(absolutePath)),
    );
  }

  Future<void> _confirmDiscard(GitFileChange change) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              title: l10n.gitDiscardConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 16),
            Text(l10n.gitDiscardConfirmBody(change.path)),
            AppDialogActions(
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
      await _cubit.discard(change);
    }
  }

  Future<void> _openBranchSheet(GitState state) async {
    final action = await GitBranchSheet.show(
      context,
      branches: state.branches,
      current: state.status.branch,
    );
    if (action == null) return;
    if (action.checkout != null) {
      await _cubit.checkoutBranch(action.checkout!);
    } else if (action.createName != null) {
      await _cubit.createBranch(action.createName!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocConsumer<GitCubit, GitState>(
        listenWhen: (prev, next) =>
            (prev.errorMessage != next.errorMessage &&
                next.errorMessage != null) ||
            prev.commitMessage != next.commitMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            AppToast.show(
              context,
              message: context.l10n.gitError(state.errorMessage ?? ''),
              variant: AppToastVariant.error,
            );
          }
          if (_commitController.text != state.commitMessage) {
            _commitController.text = state.commitMessage;
          }
        },
        builder: (context, state) => _buildBody(context, state),
      ),
    );
  }

  Widget _buildBody(BuildContext context, GitState state) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    if (!state.gitAvailable) {
      return _centeredHint(context, Icons.error_outline, l10n.gitNotInstalled);
    }
    if (!state.isRepository) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _centeredHint(
        context,
        Icons.source_outlined,
        l10n.gitNotARepository,
      );
    }

    final branch = state.status.branch ?? 'HEAD';

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            branch: branch,
            ahead: state.status.ahead,
            behind: state.status.behind,
            busy: state.busy || state.isLoading,
            treeView: state.changesViewMode == GitChangesViewMode.tree,
            allFoldersExpanded: state.allChangeFoldersExpanded,
            onRefresh: () => unawaited(_cubit.refresh()),
            onPush: () => unawaited(_cubit.push()),
            onPull: () => unawaited(_cubit.pull()),
            onBranch: () => unawaited(_openBranchSheet(state)),
            onToggleViewMode: _cubit.toggleChangesViewMode,
            onToggleExpandAll: _cubit.toggleExpandAllFolders,
          ),
          const SizedBox(height: 10),
          _CommitBox(
            controller: _commitController,
            hint: l10n.gitCommitMessageHint(branch),
            canCommit: state.status.staged.isNotEmpty && !state.busy,
            canGenerate: state.status.staged.isNotEmpty && !state.busy,
            generating: state.generatingCommitMessage,
            onChanged: _cubit.setCommitMessage,
            onCommit: () async {
              final ok = await _cubit.commit();
              if (ok) _commitController.clear();
            },
            onGenerate: () async {
              final stored = context
                  .read<AiFeatureSettingsCubit>()
                  .state
                  .settingFor(AiFeatureId.commitMessage);
              final appProviders = context.read<AppProviderCubit>().state;
              final registry = CliToolRegistryScope.of(context);
              final presets = context.read<CliPresetsCubit>().state.presets;
              if (!aiFeatureIsConfigured(
                stored: stored,
                registry: registry,
                appProviders: appProviders,
                globalPresets: presets,
              )) {
                AppToast.show(
                  context,
                  message: l10n.gitGenerateCommitMessageNoProvider,
                  variant: AppToastVariant.error,
                );
                return;
              }
              final setting = resolveAiFeatureSetting(
                stored: stored,
                appProviders: appProviders,
                registry: registry,
                globalPresets: presets,
              );
              await _cubit.generateCommitMessage(setting);
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.status.hasChanges
                ? BlocSelector<
                    GitCubit,
                    GitState,
                    (
                      GitChangesViewMode,
                      List<GitFileChange>,
                      List<GitFileChange>,
                      Set<String>,
                    )
                  >(
                    selector: (state) => (
                      state.changesViewMode,
                      state.status.staged,
                      state.status.unstaged,
                      state.expandedFolderPaths,
                    ),
                    builder: (context, changesData) {
                      final (
                        viewMode,
                        staged,
                        unstaged,
                        expandedFolderPaths,
                      ) = changesData;
                      return _GitChangesScrollBody(
                        viewMode: viewMode,
                        staged: staged,
                        unstaged: unstaged,
                        expandedFolderPaths: expandedFolderPaths,
                        cubit: _cubit,
                        changesScrollController: _changesScrollController,
                        horizontalScrollController: _horizontalScrollController,
                        onOpenDiff: (change) => unawaited(_openDiff(change)),
                        onConfirmDiscard: (change) =>
                            unawaited(_confirmDiscard(change)),
                      );
                    },
                  )
                : Center(
                    child: Text(
                      l10n.gitNoChanges,
                      style: AppTextStyles.of(
                        context,
                      ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _centeredHint(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.of(
                context,
              ).bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _GitChangesScrollBody extends StatefulWidget {
  const _GitChangesScrollBody({
    required this.viewMode,
    required this.staged,
    required this.unstaged,
    required this.expandedFolderPaths,
    required this.cubit,
    required this.changesScrollController,
    required this.horizontalScrollController,
    required this.onOpenDiff,
    required this.onConfirmDiscard,
  });

  final GitChangesViewMode viewMode;
  final List<GitFileChange> staged;
  final List<GitFileChange> unstaged;
  final Set<String> expandedFolderPaths;
  final GitCubit cubit;
  final ScrollController changesScrollController;
  final ScrollController horizontalScrollController;
  final ValueChanged<GitFileChange> onOpenDiff;
  final ValueChanged<GitFileChange> onConfirmDiscard;

  @override
  State<_GitChangesScrollBody> createState() => _GitChangesScrollBodyState();
}

class _GitChangesScrollBodyState extends State<_GitChangesScrollBody> {
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
    if (widget.viewMode == GitChangesViewMode.list) {
      final sections = <Widget>[
        if (widget.staged.isNotEmpty)
          _Section(
            title: l10n.gitStagedChanges,
            count: widget.staged.length,
            action: AppIconButton(
              icon: Icons.remove,
              compact: true,
              size: AppIconButton.kCompactSize,
              tooltip: l10n.gitUnstageAll,
              onTap: () => unawaited(widget.cubit.unstageAll()),
            ),
            children: [
              for (final change in widget.staged)
                GitChangeTile(
                  key: ValueKey('staged:${change.path}'),
                  change: change,
                  hoverEnabled: _hoverEnabled,
                  onOpenDiff: () => widget.onOpenDiff(change),
                  onStage: () {},
                  onUnstage: () => unawaited(widget.cubit.unstage(change)),
                  onDiscard: () {},
                ),
            ],
          ),
        if (widget.unstaged.isNotEmpty)
          _Section(
            title: l10n.gitChanges,
            count: widget.unstaged.length,
            action: AppIconButton(
              icon: Icons.add,
              compact: true,
              size: AppIconButton.kCompactSize,
              tooltip: l10n.gitStageAll,
              onTap: () => unawaited(widget.cubit.stageAll()),
            ),
            children: [
              for (final change in widget.unstaged)
                GitChangeTile(
                  key: ValueKey('unstaged:${change.path}'),
                  change: change,
                  hoverEnabled: _hoverEnabled,
                  onOpenDiff: () => widget.onOpenDiff(change),
                  onStage: () => unawaited(widget.cubit.stage(change)),
                  onUnstage: () {},
                  onDiscard: () => widget.onConfirmDiscard(change),
                ),
            ],
          ),
      ];
      return NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView(
          controller: widget.changesScrollController,
          cacheExtent: 400,
          children: sections,
        ),
      );
    }

    final stagedRows = visibleGitChangesRows(
      changes: widget.staged,
      expandedFolderPaths: widget.expandedFolderPaths,
    );
    final unstagedRows = visibleGitChangesRows(
      changes: widget.unstaged,
      expandedFolderPaths: widget.expandedFolderPaths,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final fileLabelStyle = AppTextStyles.of(context).bodySmall;
        final folderLabelStyle = AppTextStyles.of(
          context,
        ).bodySmall.copyWith(fontWeight: FontWeight.w500);
        final contentWidth = math.max(
          constraints.maxWidth,
          gitChangesMinContentWidth(
            rows: [...stagedRows, ...unstagedRows],
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
                controller: widget.changesScrollController,
                thumbVisibility: true,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: CustomScrollView(
                    controller: widget.changesScrollController,
                    cacheExtent: 400,
                    slivers: [
                      if (widget.staged.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: l10n.gitStagedChanges,
                            count: widget.staged.length,
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
                      if (widget.unstaged.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: l10n.gitChanges,
                            count: widget.unstaged.length,
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
        name: row.name!,
        depth: row.depth,
        isExpanded: widget.expandedFolderPaths.contains(row.folderPath),
        hoverEnabled: _hoverEnabled,
        onToggle: () => widget.cubit.toggleFolderExpanded(row.folderPath!),
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
      treeLayout: true,
      hoverEnabled: _hoverEnabled,
      onOpenDiff: () => widget.onOpenDiff(change),
      onStage: staged ? () {} : () => unawaited(widget.cubit.stage(change)),
      onUnstage: staged ? () => unawaited(widget.cubit.unstage(change)) : () {},
      onDiscard: staged ? () {} : () => widget.onConfirmDiscard(change),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.action,
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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          action,
          const SizedBox(width: 2),
          _CountBadge(count: count),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.busy,
    required this.treeView,
    required this.allFoldersExpanded,
    required this.onRefresh,
    required this.onPush,
    required this.onPull,
    required this.onBranch,
    required this.onToggleViewMode,
    required this.onToggleExpandAll,
  });

  final String branch;
  final int ahead;
  final int behind;
  final bool busy;
  final bool treeView;
  final bool allFoldersExpanded;
  final VoidCallback onRefresh;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onBranch;
  final VoidCallback onToggleViewMode;
  final VoidCallback onToggleExpandAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onBranch,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.of(
                        context,
                      ).bodySmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (ahead > 0 || behind > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.gitAheadBehind(ahead, behind),
                      style: AppTextStyles.of(
                        context,
                      ).caption.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        AppIconButton(
          icon: treeView ? Icons.view_list : Icons.account_tree_outlined,
          compact: true, size: AppIconButton.kCompactSize,
          tooltip: treeView ? l10n.gitChangesListView : l10n.gitChangesTreeView,
          onTap: onToggleViewMode,
        ),
        if (treeView)
          AppIconButton(
            icon: allFoldersExpanded
                ? Icons.unfold_less
                : Icons.unfold_more,
            compact: true,
            size: AppIconButton.kCompactSize,
            tooltip: allFoldersExpanded
                ? l10n.treeCollapseAllFolders
                : l10n.treeExpandAllFolders,
            onTap: onToggleExpandAll,
          ),
        AppIconButton(
          icon: Icons.download_outlined,
          compact: true, size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPull,
          onTap: onPull,
        ),
        AppIconButton(
          icon: Icons.upload_outlined,
          compact: true, size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPush,
          onTap: onPush,
        ),
        AppIconButton(
          icon: Icons.refresh,
          compact: true, size: AppIconButton.kCompactSize,
          tooltip: l10n.gitRefresh,
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _CommitBox extends StatelessWidget {
  const _CommitBox({
    required this.controller,
    required this.hint,
    required this.canCommit,
    required this.canGenerate,
    required this.generating,
    required this.onChanged,
    required this.onCommit,
    required this.onGenerate,
  });

  final TextEditingController controller;
  final String hint;
  final bool canCommit;
  final bool canGenerate;
  final bool generating;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                enabled: !generating,
                decoration: InputDecoration(hintText: hint, isDense: true),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('git-generate-commit-button'),
              tooltip: l10n.gitGenerateCommitMessage,
              onPressed: (canGenerate && !generating) ? onGenerate : null,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.auto_awesome_outlined, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canCommit ? onCommit : null,
          icon: Icon(Icons.check, size: 16),
          label: Text(l10n.gitCommit),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.action,
    required this.children,
  });

  final String title;
  final int count;
  final Widget action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title, count: count, action: action),
        ...children,
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

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
