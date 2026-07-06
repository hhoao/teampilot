import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/git/git_service.dart';
import '../../../services/git/worktree_branch_options.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';

export '../../../services/git/worktree_branch_options.dart'
    show suggestWorktreeBranchName;

/// Result of [showWorktreeCreateDialog]; null when the user cancels.
class WorktreeCreateResult {
  const WorktreeCreateResult({
    required this.worktreePath,
    required this.branch,
    required this.baseRef,
    required this.existingBranch,
    required this.startConversation,
  });

  /// Absolute path where the worktree will be created.
  final String worktreePath;

  /// Branch name (new branch to create, or existing branch to check out).
  final String branch;

  /// Base ref for a new branch; null/empty means current HEAD.
  final String? baseRef;

  /// True → check out an existing branch; false → create a new branch.
  final bool existingBranch;

  /// True → open a new conversation in the worktree after creating it.
  final bool startConversation;
}

/// Loads branch choices for the existing-branch picker (local + remote-only).
typedef BranchListLoader =
    Future<List<WorktreeBranchOption>> Function(String repoPath);

/// Collects inputs for creating a git worktree. Pure UI — it does NOT run git;
/// the caller performs `git worktree add` with the returned result.
Future<WorktreeCreateResult?> showWorktreeCreateDialog(
  BuildContext context, {
  required String repoName,
  required String repoPath,
  required WorktreeLayoutPathResolver layout,
  required BranchListLoader branchLoader,
  bool showStartConversationOption = true,
}) {
  return showDialog<WorktreeCreateResult>(
    context: context,
    builder: (_) => _WorktreeCreateDialog(
      repoName: repoName,
      repoPath: repoPath,
      layout: layout,
      branchLoader: branchLoader,
      showStartConversationOption: showStartConversationOption,
    ),
  );
}

BranchListLoader branchListLoaderFor(RuntimeContext workContext) {
  return (repoPath) async {
    final git =
        GitService.debugOverrideFactory?.call() ??
        GitService.forContext(workContext);
    final local = await git.branches(repoPath);
    List<String> remote = const [];
    try {
      remote = await git.remoteBranches(repoPath);
    } on Object {
      // Remote listing is optional; local branches are still usable.
    }
    return mergeWorktreeBranchOptions(local: local, remote: remote);
  };
}

/// Minimal seam over [WorkspaceLayout.worktreePathFor] so the dialog can preview
/// the target path without constructing storage objects itself.
typedef WorktreeLayoutPathResolver =
    String Function({required String repoName, required String branch});

class _WorktreeCreateDialog extends StatefulWidget {
  const _WorktreeCreateDialog({
    required this.repoName,
    required this.repoPath,
    required this.layout,
    required this.branchLoader,
    required this.showStartConversationOption,
  });

  final String repoName;
  final String repoPath;
  final WorktreeLayoutPathResolver layout;
  final BranchListLoader branchLoader;
  final bool showStartConversationOption;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  final _branch = TextEditingController();
  final _base = TextEditingController();
  bool _existingBranch = false;
  bool _startConversation = true;
  List<WorktreeBranchOption> _branchOptions = const [];
  WorktreeBranchOption? _selectedBranch;
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    if (!widget.showStartConversationOption) {
      _startConversation = false;
    }
    _branch.addListener(() => setState(() {}));
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await widget.branchLoader(widget.repoPath);
      if (!mounted) return;
      setState(() {
        _branchOptions = list;
        _loadingBranches = false;
        if (_branch.text.trim().isEmpty && list.isNotEmpty) {
          _branch.text = suggestWorktreeBranchName(list.first.name);
        }
        _selectedBranch ??= list.isNotEmpty ? list.first : null;
      });
    } on Object {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  @override
  void dispose() {
    _branch.dispose();
    _base.dispose();
    super.dispose();
  }

  String get _previewBranchName {
    if (_existingBranch && _selectedBranch != null) {
      return _selectedBranch!.name;
    }
    return _branch.text.trim();
  }

  String get _previewPath => _previewBranchName.isEmpty
      ? ''
      : widget.layout(
          repoName: widget.repoName,
          branch: _previewBranchName,
        );

  bool get _canCreate =>
      _existingBranch
          ? _selectedBranch != null
          : _branch.text.trim().isNotEmpty;

  void _selectBranchOption(WorktreeBranchOption option) {
    setState(() {
      _selectedBranch = option;
      _branch.text = option.name;
    });
  }

  WorktreeCreateResult _buildResult() {
    if (_existingBranch && _selectedBranch != null) {
      final option = _selectedBranch!;
      return WorktreeCreateResult(
        worktreePath: _previewPath,
        branch: option.name,
        baseRef: option.remoteRef,
        existingBranch: option.isLocal,
        startConversation: widget.showStartConversationOption
            ? _startConversation
            : false,
      );
    }
    final branch = _branch.text.trim();
    final base = _base.text.trim();
    return WorktreeCreateResult(
      worktreePath: _previewPath,
      branch: branch,
      baseRef: base.isEmpty ? null : base,
      existingBranch: false,
      startConversation: widget.showStartConversationOption
          ? _startConversation
          : false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.worktreeCreateTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.worktreeModeNewBranch),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.worktreeModeExistingBranch),
                ),
              ],
              selected: {_existingBranch},
              onSelectionChanged: (s) {
                setState(() {
                  _existingBranch = s.first;
                  if (_existingBranch && _branchOptions.isNotEmpty) {
                    final current = _selectedBranch ?? _branchOptions.first;
                    if (!_branchOptions.contains(current)) {
                      _selectBranchOption(_branchOptions.first);
                    } else {
                      _selectBranchOption(current);
                    }
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (_existingBranch && _branchOptions.isNotEmpty)
              AppDropdownField<WorktreeBranchOption>(
                items: _branchOptions,
                initialItem:
                    _selectedBranch != null &&
                        _branchOptions.contains(_selectedBranch)
                    ? _selectedBranch
                    : _branchOptions.first,
                decoration: AppDropdownDecorations.themed(context),
                onChanged: (value) {
                  if (value != null) _selectBranchOption(value);
                },
                itemLabel: (option) => option.displayLabel,
              )
            else
              TextField(
                controller: _branch,
                autofocus: !_existingBranch,
                decoration: InputDecoration(
                  labelText: l10n.worktreeBranchLabel,
                  suffixIcon: _loadingBranches
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            if (!_existingBranch) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _base,
                decoration: InputDecoration(
                  labelText: l10n.worktreeBaseRefLabel,
                  hintText: l10n.worktreeBaseRefHint,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_previewPath.isNotEmpty) ...[
              Text(l10n.worktreePathLabel, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                _previewPath,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            if (widget.showStartConversationOption)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _startConversation,
                onChanged: (v) =>
                    setState(() => _startConversation = v ?? false),
                title: Text(l10n.worktreeStartConversation),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _canCreate
              ? () => Navigator.of(context).pop(_buildResult())
              : null,
          child: Text(l10n.worktreeCreateAction),
        ),
      ],
    );
  }
}
