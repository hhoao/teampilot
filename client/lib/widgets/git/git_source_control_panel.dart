import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/git_cubit.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../models/ai_feature_setting.dart';
import '../../services/ai/ai_feature_setting_resolver.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
import 'git_branch_menu.dart';
import 'git_change_folder_tile.dart';
import 'git_change_tile.dart';
import 'git_diff_view.dart';

const _gitChangesRowPadding = EdgeInsets.symmetric(
  horizontal: kGitChangesRowHorizontalPadding,
  vertical: kGitChangesRowVerticalPadding,
);

/// VSCode-style "Source Control" panel for the editor workbench left rail.
///
/// Self-contained like `_FileTreePanel`: builds its own [GitCubit] and tracks
/// the active session cwd via [cwd]. Desktop-local git only.
class GitSourceControlPanel extends StatefulWidget {
  const GitSourceControlPanel({required this.cwd, super.key});

  final String cwd;

  @override
  State<GitSourceControlPanel> createState() => _GitSourceControlPanelState();
}

class _GitSourceControlPanelState extends State<GitSourceControlPanel> {
  final _cubit = GitCubit();
  final _commitController = TextEditingController();
  final _changesScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_cubit.setRepoRoot(widget.cwd));
  }

  @override
  void didUpdateWidget(covariant GitSourceControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd) {
      unawaited(_cubit.setRepoRoot(widget.cwd));
    }
  }

  @override
  void dispose() {
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
      builder: (ctx) => AlertDialog(
        title: Text(l10n.gitDiscardConfirmTitle),
        content: Text(l10n.gitDiscardConfirmBody(change.path)),
        actions: [
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.l10n.gitError(state.errorMessage ?? '')),
              ),
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
            onRefresh: () => unawaited(_cubit.refresh()),
            onPush: () => unawaited(_cubit.push()),
            onPull: () => unawaited(_cubit.pull()),
            onBranch: () => unawaited(_openBranchSheet(state)),
            onToggleViewMode: _cubit.toggleChangesViewMode,
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
              final setting = resolveAiFeatureSetting(
                stored: context
                    .read<AiFeatureSettingsCubit>()
                    .state
                    .settingFor(AiFeatureId.commitMessage),
                appProviders: context.read<AppProviderCubit>().state,
                registry: CliToolRegistryScope.of(context),
              );
              if (setting.providerId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.gitGenerateCommitMessageNoProvider),
                  ),
                );
                return;
              }
              await _cubit.generateCommitMessage(setting);
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.status.hasChanges
                ? _buildChangesBody(context, state)
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

  Widget _buildChangesBody(BuildContext context, GitState state) {
    final l10n = context.l10n;
    final sections = <Widget>[
      if (state.status.staged.isNotEmpty)
        _Section(
          title: l10n.gitStagedChanges,
          count: state.status.staged.length,
          action: AppIconButton(
            icon: Icons.remove,
            iconSize: AppIconButton.kCompactIconSize,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.gitUnstageAll,
            onTap: () => unawaited(_cubit.unstageAll()),
          ),
          children: _buildSectionChildren(
            context,
            state,
            state.status.staged,
            staged: true,
          ),
        ),
      if (state.status.unstaged.isNotEmpty)
        _Section(
          title: l10n.gitChanges,
          count: state.status.unstaged.length,
          action: AppIconButton(
            icon: Icons.add,
            iconSize: AppIconButton.kCompactIconSize,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.gitStageAll,
            onTap: () => unawaited(_cubit.stageAll()),
          ),
          children: _buildSectionChildren(
            context,
            state,
            state.status.unstaged,
            staged: false,
          ),
        ),
    ];

    if (state.changesViewMode == GitChangesViewMode.list) {
      return ListView(children: sections);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fileLabelStyle = AppTextStyles.of(context).bodySmall;
        final folderLabelStyle = AppTextStyles.of(
          context,
        ).bodySmall.copyWith(fontWeight: FontWeight.w500);
        final treeRows = [
          ...visibleGitChangesRows(
            changes: state.status.staged,
            expandedFolderPaths: state.expandedFolderPaths,
          ),
          ...visibleGitChangesRows(
            changes: state.status.unstaged,
            expandedFolderPaths: state.expandedFolderPaths,
          ),
        ];
        final contentWidth = math.max(
          constraints.maxWidth,
          gitChangesMinContentWidth(
            rows: treeRows,
            fileLabelStyle: fileLabelStyle,
            folderLabelStyle: folderLabelStyle,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        );

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Scrollbar(
                controller: _changesScrollController,
                thumbVisibility: true,
                child: ListView(
                  controller: _changesScrollController,
                  children: sections,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildSectionChildren(
    BuildContext context,
    GitState state,
    List<GitFileChange> changes, {
    required bool staged,
  }) {
    if (state.changesViewMode == GitChangesViewMode.list) {
      return [
        for (final change in changes)
          GitChangeTile(
            change: change,
            onOpenDiff: () => unawaited(_openDiff(change)),
            onStage: staged ? () {} : () => unawaited(_cubit.stage(change)),
            onUnstage: staged ? () => unawaited(_cubit.unstage(change)) : () {},
            onDiscard: staged
                ? () {}
                : () => unawaited(_confirmDiscard(change)),
          ),
      ];
    }

    final rows = visibleGitChangesRows(
      changes: changes,
      expandedFolderPaths: state.expandedFolderPaths,
    );
    return [
      for (final row in rows)
        SizedBox(
          width: double.infinity,
          height: kGitChangesRowExtent,
          child: Padding(
            padding: _gitChangesRowPadding,
            child: row.isFolder
                ? GitChangeFolderTile(
                    name: row.name!,
                    depth: row.depth,
                    isExpanded: state.expandedFolderPaths.contains(
                      row.folderPath,
                    ),
                    onToggle: () =>
                        _cubit.toggleFolderExpanded(row.folderPath!),
                  )
                : GitChangeTile(
                    change: row.change!,
                    depth: row.depth,
                    treeLayout: true,
                    onOpenDiff: () => unawaited(_openDiff(row.change!)),
                    onStage: staged
                        ? () {}
                        : () => unawaited(_cubit.stage(row.change!)),
                    onUnstage: staged
                        ? () => unawaited(_cubit.unstage(row.change!))
                        : () {},
                    onDiscard: staged
                        ? () {}
                        : () => unawaited(_confirmDiscard(row.change!)),
                  ),
          ),
        ),
    ];
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

class _Header extends StatelessWidget {
  const _Header({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.busy,
    required this.treeView,
    required this.onRefresh,
    required this.onPush,
    required this.onPull,
    required this.onBranch,
    required this.onToggleViewMode,
  });

  final String branch;
  final int ahead;
  final int behind;
  final bool busy;
  final bool treeView;
  final VoidCallback onRefresh;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onBranch;
  final VoidCallback onToggleViewMode;

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
          iconSize: AppIconButton.kCompactIconSize,
          size: AppIconButton.kCompactSize,
          tooltip: treeView ? l10n.gitChangesListView : l10n.gitChangesTreeView,
          onTap: onToggleViewMode,
        ),
        AppIconButton(
          icon: Icons.download_outlined,
          iconSize: AppIconButton.kCompactIconSize,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPull,
          onTap: onPull,
        ),
        AppIconButton(
          icon: Icons.upload_outlined,
          iconSize: AppIconButton.kCompactIconSize,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPush,
          onTap: onPush,
        ),
        AppIconButton(
          icon: Icons.refresh,
          iconSize: AppIconButton.kCompactIconSize,
          size: AppIconButton.kCompactSize,
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
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: canCommit ? onCommit : null,
          icon: const Icon(Icons.check, size: 16),
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
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
        ),
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
