import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/git_worktree.dart';
import '../../../models/workspace.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import 'workspace_landing_selectors.dart';
import 'package:shared_ui/shared_ui.dart';

/// Inline project + worktree pickers shared by landing-aligned launch forms.
class WorkspaceLandingLocationFields extends StatefulWidget {
  const WorkspaceLandingLocationFields({
    required this.workspace,
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.labelWidth,
    required this.onProjectChanged,
    required this.onWorktreeChanged,
    super.key,
  });

  final Workspace workspace;
  final String? projectFolderPath;
  final String? workingDirectoryPath;
  final double labelWidth;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<String?> onWorktreeChanged;

  @override
  State<WorkspaceLandingLocationFields> createState() =>
      _WorkspaceLandingLocationFieldsState();
}

class _WorkspaceLandingLocationFieldsState
    extends State<WorkspaceLandingLocationFields> {
  var _syncGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_syncWorktreesFromStoredPaths());
  }

  @override
  void didUpdateWidget(covariant WorkspaceLandingLocationFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.workspaceId != widget.workspace.workspaceId ||
        oldWidget.projectFolderPath != widget.projectFolderPath ||
        oldWidget.workingDirectoryPath != widget.workingDirectoryPath) {
      unawaited(_syncWorktreesFromStoredPaths());
    }
  }

  WorkspaceLandingProjectResolver get _projectResolver =>
      WorkspaceLandingProjectResolver(
        workspace: widget.workspace,
        storedProjectPath: widget.projectFolderPath,
      );

  WorkspaceLandingWorktreeResolver _worktreeResolver(WorktreeState? state) {
    final projectPath = _projectResolver.resolveSelectedProjectPath();
    List<GitWorktree> cached = const [];
    try {
      cached = context.read<WorktreeCubit>().worktreesForProject(projectPath);
    } on ProviderNotFoundException {
      cached = const [];
    }
    return WorkspaceLandingWorktreeResolver(
      projectPath: projectPath,
      worktreeState: state,
      storedWorktreePath: widget.workingDirectoryPath,
      cachedWorktrees: cached,
    );
  }

  WorktreeCubit? get _worktreeCubit {
    try {
      return context.read<WorktreeCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _syncWorktreesFromStoredPaths() async {
    final generation = ++_syncGeneration;
    final cubit = _worktreeCubit;
    final projectPath = _projectResolver.resolveSelectedProjectPath();
    if (cubit == null || projectPath.trim().isEmpty) return;

    try {
      if (cubit.state.loading) {
        await cubit.stream.firstWhere((s) => !s.loading);
        if (!mounted || generation != _syncGeneration) return;
      }
      await cubit.selectProject(
        projectPath,
        preferWorktreePath: widget.workingDirectoryPath,
      );
      if (!mounted || generation != _syncGeneration) return;
      final resolved = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      final normalized = normalizeWorkspacePath(resolved);
      final stored = widget.workingDirectoryPath?.trim() ?? '';
      if (stored.isEmpty || !workspacePathsEqual(stored, normalized)) {
        widget.onWorktreeChanged(normalized);
      }
    } on ProviderNotFoundException {
      // Dialog rendered outside workspace tools scope.
    }
  }

  Future<void> _onProjectSelected(Object? value) async {
    if (value is! String || value.trim().isEmpty) return;
    final projectPath = normalizeWorkspacePath(value);
    widget.onProjectChanged(projectPath);

    final cubit = _worktreeCubit;
    if (cubit == null) {
      widget.onWorktreeChanged(projectPath);
      return;
    }

    final generation = ++_syncGeneration;
    try {
      if (cubit.state.loading) {
        await cubit.stream.firstWhere((s) => !s.loading);
        if (!mounted || generation != _syncGeneration) return;
      }
      await cubit.selectProject(projectPath);
      if (!mounted || generation != _syncGeneration) return;
      final resolved = _worktreeResolver(
        cubit.state,
      ).resolveSelectedWorktreePath();
      widget.onWorktreeChanged(normalizeWorkspacePath(resolved));
    } on ProviderNotFoundException {
      widget.onWorktreeChanged(projectPath);
    }
  }

  void _onWorktreeSelected(Object? value) {
    if (value is! String || value.trim().isEmpty) return;
    widget.onWorktreeChanged(normalizeWorkspacePath(value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final projectResolver = _projectResolver;
    WorktreeState? worktreeState;
    try {
      final bits = context
          .select<WorktreeCubit, (String, List<GitWorktree>, String, bool)>(
            (c) => (
              c.state.repoPath,
              c.state.worktrees,
              c.state.currentWorktreePath,
              c.state.loading,
            ),
          );
      worktreeState = WorktreeState(
        repoPath: bits.$1,
        worktrees: bits.$2,
        currentWorktreePath: bits.$3,
        loading: bits.$4,
      );
    } on ProviderNotFoundException {
      worktreeState = null;
    }

    final selectedProjectPath = projectResolver.resolveSelectedProjectPath();
    final worktreeResolver = _worktreeResolver(worktreeState);
    final selectedWorktreePath = worktreeResolver.resolveSelectedWorktreePath();
    final projectOptions = projectResolver.options;
    final showProjectPicker = projectOptions.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showProjectPicker) ...[
          TpFormField<String>(
            key: ValueKey('project-$selectedProjectPath'),
            id: 'projectFolderPath',
            initialValue: selectedProjectPath,
            label: Text(l10n.automationsLaunchProject),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: widget.labelWidth,
            builder: (state) {
              return WorkspaceLandingSelectorBar(
                label: projectResolver.labelFor(selectedProjectPath),
                hintWhenEmpty: l10n.workspaceChatLandingSelectProject,
                menuSpecs: projectResolver.menuSpecs(selectedProjectPath),
                onSelected: (value) {
                  if (value is! String) return;
                  state.didChange(value);
                  unawaited(_onProjectSelected(value));
                },
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (worktreeResolver.showsWorktreeSelector) ...[
          TpFormField<String>(
            key: ValueKey('worktree-$selectedWorktreePath'),
            id: 'workingDirectoryPath',
            initialValue: selectedWorktreePath,
            label: Text(l10n.automationsLaunchWorktree),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: widget.labelWidth,
            builder: (state) {
              return WorkspaceLandingSelectorBar(
                label: worktreeResolver.labelFor(selectedWorktreePath),
                hintWhenEmpty: l10n.workspaceChatLandingSelectWorktree,
                menuSpecs: worktreeResolver.menuSpecs(selectedWorktreePath),
                onSelected: (value) {
                  if (value is! String) return;
                  state.didChange(value);
                  _onWorktreeSelected(value);
                },
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
