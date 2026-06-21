import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';

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

/// Collects inputs for creating a git worktree. Pure UI — it does NOT run git;
/// the caller performs `git worktree add` with the returned result.
Future<WorktreeCreateResult?> showWorktreeCreateDialog(
  BuildContext context, {
  required String repoName,
  required WorktreeLayoutPathResolver layout,
}) {
  return showDialog<WorktreeCreateResult>(
    context: context,
    builder: (_) => _WorktreeCreateDialog(repoName: repoName, layout: layout),
  );
}

/// Minimal seam over [WorkspaceLayout.worktreePathFor] so the dialog can preview
/// the target path without constructing storage objects itself.
typedef WorktreeLayoutPathResolver = String Function({
  required String repoName,
  required String branch,
});

class _WorktreeCreateDialog extends StatefulWidget {
  const _WorktreeCreateDialog({required this.repoName, required this.layout});

  final String repoName;
  final WorktreeLayoutPathResolver layout;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  final _branch = TextEditingController();
  final _base = TextEditingController();
  bool _existingBranch = false;
  bool _startConversation = true;

  @override
  void initState() {
    super.initState();
    _branch.addListener(() => setState(() {}));
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
              onSelectionChanged: (s) => setState(() => _existingBranch = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _branch,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.worktreeBranchLabel),
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
