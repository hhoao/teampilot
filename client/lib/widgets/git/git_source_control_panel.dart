import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../cubits/editor_cubit.dart';
import '../../cubits/git_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_status.dart';
import '../../theme/app_text_styles.dart';
import '../app_icon_button.dart';
import 'git_branch_menu.dart';
import 'git_change_tile.dart';
import 'git_diff_view.dart';

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
            prev.errorMessage != next.errorMessage &&
            next.errorMessage != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.gitError(state.errorMessage ?? '')),
            ),
          );
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
            onRefresh: () => unawaited(_cubit.refresh()),
            onPush: () => unawaited(_cubit.push()),
            onPull: () => unawaited(_cubit.pull()),
            onBranch: () => unawaited(_openBranchSheet(state)),
          ),
          const SizedBox(height: 10),
          _CommitBox(
            controller: _commitController,
            hint: l10n.gitCommitMessageHint(branch),
            canCommit: state.status.staged.isNotEmpty && !state.busy,
            onChanged: _cubit.setCommitMessage,
            onCommit: () async {
              final ok = await _cubit.commit();
              if (ok) _commitController.clear();
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.status.hasChanges
                ? ListView(
                    children: [
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
                          children: [
                            for (final c in state.status.staged)
                              GitChangeTile(
                                change: c,
                                onOpenDiff: () => unawaited(_openDiff(c)),
                                onStage: () {},
                                onUnstage: () => unawaited(_cubit.unstage(c)),
                                onDiscard: () {},
                              ),
                          ],
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
                          children: [
                            for (final c in state.status.unstaged)
                              GitChangeTile(
                                change: c,
                                onOpenDiff: () => unawaited(_openDiff(c)),
                                onStage: () => unawaited(_cubit.stage(c)),
                                onUnstage: () {},
                                onDiscard: () =>
                                    unawaited(_confirmDiscard(c)),
                              ),
                          ],
                        ),
                    ],
                  )
                : Center(
                    child: Text(
                      l10n.gitNoChanges,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.busy,
    required this.onRefresh,
    required this.onPush,
    required this.onPull,
    required this.onBranch,
  });

  final String branch;
  final int ahead;
  final int behind;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onBranch;

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
                  Icon(Icons.account_tree_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (ahead > 0 || behind > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      l10n.gitAheadBehind(ahead, behind),
                      style: AppTextStyles.of(context).caption.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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
    required this.onChanged,
    required this.onCommit,
  });

  final TextEditingController controller;
  final String hint;
  final bool canCommit;
  final ValueChanged<String> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
          ),
          onChanged: onChanged,
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
        style: AppTextStyles.of(context).caption.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
