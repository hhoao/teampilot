import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/git/git_service.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';

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

/// Loads local branch names for the existing-branch picker.
typedef BranchListLoader = Future<List<String>> Function(String repoPath);

/// Collects inputs for creating a git worktree. Pure UI — it does NOT run git;
/// the caller performs `git worktree add` with the returned result.
Future<WorktreeCreateResult?> showWorktreeCreateDialog(
  BuildContext context, {
  required String repoName,
  required String repoPath,
  required WorktreeLayoutPathResolver layout,
  BranchListLoader? branchLoader,
}) {
  return showDialog<WorktreeCreateResult>(
    context: context,
    builder: (_) => _WorktreeCreateDialog(
      repoName: repoName,
      repoPath: repoPath,
      layout: layout,
      branchLoader: branchLoader ?? _defaultBranchLoader,
    ),
  );
}

Future<List<String>> _defaultBranchLoader(String repoPath) async {
  final git = GitService.debugOverrideFactory?.call() ?? GitService();
  return git.branches(repoPath);
}

/// Suggest a new worktree branch name from the repo's current/default branch.
String suggestWorktreeBranchName(String? currentBranch) {
  final base = (currentBranch ?? '').trim();
  if (base.isEmpty) return 'worktree';
  return '$base-wt';
}

/// Minimal seam over [WorkspaceLayout.worktreePathFor] so the dialog can preview
/// the target path without constructing storage objects itself.
typedef WorktreeLayoutPathResolver = String Function({
  required String repoName,
  required String branch,
});

class _WorktreeCreateDialog extends StatefulWidget {
  const _WorktreeCreateDialog({
    required this.repoName,
    required this.repoPath,
    required this.layout,
    required this.branchLoader,
  });

  final String repoName;
  final String repoPath;
  final WorktreeLayoutPathResolver layout;
  final BranchListLoader branchLoader;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  final _branch = TextEditingController();
  final _base = TextEditingController();
  bool _existingBranch = false;
  bool _startConversation = true;
  List<String> _branches = const [];
  bool _loadingBranches = true;

  @override
  void initState() {
    super.initState();
    _branch.addListener(() => setState(() {}));
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await widget.branchLoader(widget.repoPath);
      if (!mounted) return;
      setState(() {
        _branches = list;
        _loadingBranches = false;
        if (_branch.text.trim().isEmpty && list.isNotEmpty) {
          _branch.text = suggestWorktreeBranchName(list.first);
        }
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

  String get _previewPath => _branch.text.trim().isEmpty
      ? ''
      : widget.layout(repoName: widget.repoName, branch: _branch.text.trim());

  bool get _canCreate => _branch.text.trim().isNotEmpty;

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
                ButtonSegment(value: false, label: Text(l10n.worktreeModeNewBranch)),
                ButtonSegment(value: true, label: Text(l10n.worktreeModeExistingBranch)),
              ],
              selected: {_existingBranch},
              onSelectionChanged: (s) {
                setState(() {
                  _existingBranch = s.first;
                  if (_existingBranch &&
                      _branches.isNotEmpty &&
                      !_branches.contains(_branch.text.trim())) {
                    _branch.text = _branches.first;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (_existingBranch && _branches.isNotEmpty)
              AppDropdownField<String>(
                items: _branches,
                initialItem: _branches.contains(_branch.text.trim())
                    ? _branch.text.trim()
                    : _branches.first,
                decoration: AppDropdownDecorations.themed(context),
                onChanged: (value) {
                  if (value != null) _branch.text = value;
                },
                itemBuilder: (context, branch) => Text(branch),
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
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _startConversation,
              onChanged: (v) => setState(() => _startConversation = v ?? false),
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
              ? () {
                  final branch = _branch.text.trim();
                  final base = _base.text.trim();
                  Navigator.of(context).pop(WorktreeCreateResult(
                    worktreePath: _previewPath,
                    branch: branch,
                    baseRef: base.isEmpty ? null : base,
                    existingBranch: _existingBranch,
                    startConversation: _startConversation,
                  ));
                }
              : null,
          child: Text(l10n.worktreeCreateAction),
        ),
      ],
    );
  }
}
