import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../services/git/git_repo_store.dart';
import '../../services/storage/runtime_context.dart';
import '../../theme/app_text_styles.dart';
import '../app_dialog.dart';
import '../app_icon_button.dart';
import 'git_branch_menu.dart';
import 'git_changes_tree_list.dart';
import 'git_diff_view.dart';

/// VSCode-style "Source Control" panel for the editor workbench left rail.
///
/// A pure view over [GitRepoStore]: the per-root [GitCubit]s live in the store
/// (app-level), so reopening this tab paints the last-known status instantly
/// while [RightToolsPanel]'s poller keeps it fresh. The panel never spawns git
/// itself — switching to it is free.
///
/// Multi-folder workspaces: when more than one [roots] folder is mounted, a
/// repo selector switches which folder's source control is shown (each folder
/// may be its own git repository). A single folder shows it directly.
class GitSourceControlPanel extends StatefulWidget {
  const GitSourceControlPanel({
    required this.roots,
    required this.workContext,
    super.key,
  });

  /// Workspace folders (first = primary). Each may be an independent git repo.
  final List<String> roots;

  /// Work-plane context for git commands (ssh/wsl/local).
  final RuntimeContext workContext;

  @override
  State<GitSourceControlPanel> createState() => _GitSourceControlPanelState();
}

class _GitSourceControlPanelState extends State<GitSourceControlPanel> {
  String? _selectedRoot;

  /// Non-empty workspace folders, primary first.
  List<String> get _roots =>
      widget.roots.where((p) => p.isNotEmpty).toList(growable: false);

  String get _activeRoot {
    final roots = _roots;
    if (roots.isEmpty) return '';
    final selected = _selectedRoot;
    if (selected != null && roots.contains(selected)) return selected;
    return roots.first;
  }

  GitRepoStore get _store => context.read<GitRepoStore>();

  RuntimeContext get _workContext => widget.workContext;

  GitCubit _cubitFor(String root) =>
      _store.cubitFor(root, workContext: _workContext);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final active = _activeRoot;
      if (active.isNotEmpty) _cubitFor(active).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roots = _roots;
    if (roots.isEmpty) {
      return _GitCenteredHint(
        icon: Icons.source_outlined,
        text: context.l10n.gitNotARepository,
      );
    }
    if (roots.length == 1) {
      return _GitRepoBody(
        cubit: _cubitFor(roots.first),
        workContext: _workContext,
      );
    }
    final active = _activeRoot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RepoSelector(
          cubitFor: _cubitFor,
          roots: roots,
          selected: active,
          onSelect: (root) {
            setState(() => _selectedRoot = root);
            _cubitFor(root).refresh();
          },
        ),
        Expanded(
          child: _GitRepoBody(
            key: ValueKey('git-repo:$active'),
            cubit: _cubitFor(active),
            workContext: _workContext,
          ),
        ),
      ],
    );
  }
}

class _RepoSelector extends StatelessWidget {
  const _RepoSelector({
    required this.cubitFor,
    required this.roots,
    required this.selected,
    required this.onSelect,
  });

  final GitCubit Function(String root) cubitFor;
  final List<String> roots;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final root in roots)
            _RepoChip(
              cubit: cubitFor(root),
              root: root,
              selected: root == selected,
              onTap: () => onSelect(root),
            ),
        ],
      ),
    );
  }
}

class _RepoChip extends StatelessWidget {
  const _RepoChip({
    required this.cubit,
    required this.root,
    required this.selected,
    required this.onTap,
  });

  final GitCubit cubit;
  final String root;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = p.basename(root).isEmpty ? root : p.basename(root);
    return BlocProvider.value(
      value: cubit,
      child: BlocSelector<GitCubit, GitState, int>(
        selector: (state) => state.status.isRepository
            ? state.status.staged.length + state.status.unstaged.length
            : 0,
        builder: (context, count) => ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.of(context).bodySmall,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                _DirtyBadge(count: count, selected: selected),
              ],
            ],
          ),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
          tooltip: root,
          labelStyle: TextStyle(
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DirtyBadge extends StatelessWidget {
  const _DirtyBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? cs.onSecondaryContainer.withValues(alpha: 0.18)
            : cs.primaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.of(context).caption.copyWith(
          color: selected ? cs.onSecondaryContainer : cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GitRepoBody extends StatefulWidget {
  const _GitRepoBody({
    required this.cubit,
    required this.workContext,
    super.key,
  });

  final GitCubit cubit;
  final RuntimeContext workContext;

  @override
  State<_GitRepoBody> createState() => _GitRepoBodyState();
}

class _GitRepoBodyState extends State<_GitRepoBody> {
  GitCubit get _cubit => widget.cubit;

  final _commitController = TextEditingController();
  final _changesScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  var _changesListReady = false;

  @override
  void initState() {
    super.initState();
    _commitController.text = _cubit.state.commitMessage;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _changesListReady = true);
    });
  }

  @override
  void dispose() {
    _commitController.dispose();
    _changesScrollController.dispose();
    _horizontalScrollController.dispose();
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
      onOpenSource: () => unawaited(
        editor.openFile(absolutePath, fs: widget.workContext.filesystem),
      ),
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

  Future<void> _openBranchSheet() async {
    await _cubit.ensureBranches(force: true);
    if (!mounted) return;
    final action = await GitBranchSheet.show(
      context,
      branches: _cubit.state.branches,
      current: _cubit.state.status.branch,
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
        buildWhen: (prev, next) =>
            prev.gitAvailable != next.gitAvailable ||
            prev.isRepository != next.isRepository ||
            prev.isLoading != next.isLoading,
        builder: (context, state) => _buildShell(context, state),
      ),
    );
  }

  Widget _buildShell(BuildContext context, GitState state) {
    final l10n = context.l10n;

    if (!state.gitAvailable) {
      return _GitCenteredHint(
        icon: Icons.error_outline,
        text: l10n.gitNotInstalled,
      );
    }
    if (!state.isRepository) {
      if (state.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _GitCenteredHint(
        icon: Icons.source_outlined,
        text: l10n.gitNotARepository,
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlocSelector<
            GitCubit,
            GitState,
            (String, int, int, bool, bool)
          >(
            selector: (state) => (
              state.status.branch ?? 'HEAD',
              state.status.ahead,
              state.status.behind,
              state.busy || state.isLoading,
              state.allChangeFoldersExpanded,
            ),
            builder: (context, header) {
              final (branch, ahead, behind, busy, allExpanded) = header;
              return _Header(
                branch: branch,
                ahead: ahead,
                behind: behind,
                busy: busy,
                allFoldersExpanded: allExpanded,
                onRefresh: () => unawaited(_cubit.refresh()),
                onPush: () => unawaited(_cubit.push()),
                onPull: () => unawaited(_cubit.pull()),
                onBranch: () => unawaited(_openBranchSheet()),
                onToggleExpandAll: _cubit.toggleExpandAllFolders,
              );
            },
          ),
          const SizedBox(height: 10),
          BlocSelector<
            GitCubit,
            GitState,
            (bool, bool, bool, String)
          >(
            selector: (state) => (
              state.status.staged.isNotEmpty,
              state.busy,
              state.generatingCommitMessage,
              state.status.branch ?? 'HEAD',
            ),
            builder: (context, commit) {
              final (hasStaged, busy, generating, branch) = commit;
              return _CommitBox(
                controller: _commitController,
                hint: l10n.gitCommitMessageHint(branch),
                canCommit: hasStaged && !busy,
                canGenerate: hasStaged && !busy,
                generating: generating,
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
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocSelector<GitCubit, GitState, (bool, GitChangesTreeViewData)>(
              selector: (state) => (
                state.status.hasChanges,
                state.changesTreeView,
              ),
              builder: (context, data) {
                final (hasChanges, treeView) = data;
                if (!hasChanges) {
                  final cs = Theme.of(context).colorScheme;
                  return Center(
                    child: Text(
                      l10n.gitNoChanges,
                      style: AppTextStyles.of(
                        context,
                      ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                    ),
                  );
                }
                if (!_changesListReady) {
                  return const SizedBox.shrink();
                }
                return GitChangesTreeList(
                  treeView: treeView,
                  cubit: _cubit,
                  listScrollController: _changesScrollController,
                  horizontalScrollController: _horizontalScrollController,
                  onOpenDiff: (change) => unawaited(_openDiff(change)),
                  onConfirmDiscard: (change) =>
                      unawaited(_confirmDiscard(change)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GitCenteredHint extends StatelessWidget {
  const _GitCenteredHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
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
    required this.allFoldersExpanded,
    required this.onRefresh,
    required this.onPush,
    required this.onPull,
    required this.onBranch,
    required this.onToggleExpandAll,
  });

  final String branch;
  final int ahead;
  final int behind;
  final bool busy;
  final bool allFoldersExpanded;
  final VoidCallback onRefresh;
  final VoidCallback onPush;
  final VoidCallback onPull;
  final VoidCallback onBranch;
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
          icon: allFoldersExpanded ? Icons.unfold_less : Icons.unfold_more,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: allFoldersExpanded
              ? l10n.treeCollapseAllFolders
              : l10n.treeExpandAllFolders,
          onTap: onToggleExpandAll,
        ),
        AppIconButton(
          icon: Icons.download_outlined,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPull,
          onTap: onPull,
        ),
        AppIconButton(
          icon: Icons.upload_outlined,
          compact: true,
          size: AppIconButton.kCompactSize,
          tooltip: l10n.gitPush,
          onTap: onPush,
        ),
        AppIconButton(
          icon: Icons.refresh,
          compact: true,
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
