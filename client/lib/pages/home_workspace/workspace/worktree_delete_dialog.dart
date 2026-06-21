import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';

/// Result of [showWorktreeDeleteDialog]; null when the user cancels.
class WorktreeDeleteResult {
  const WorktreeDeleteResult({
    required this.force,
    required this.deleteBranch,
    required this.deleteSessions,
  });

  /// Pass `--force` to `git worktree remove` (needed when the tree is dirty).
  final bool force;

  /// Also run `git branch -d` for the worktree's branch.
  final bool deleteBranch;

  /// Also delete the conversations that live in this worktree.
  final bool deleteSessions;
}

/// Confirms removing a git worktree. Pure UI — the caller runs git and deletes
/// sessions based on the returned flags. [sessionCount] is the number of
/// conversations under the worktree (the "also delete sessions" row is hidden
/// when zero).
Future<WorktreeDeleteResult?> showWorktreeDeleteDialog(
  BuildContext context, {
  required String branchLabel,
  required int sessionCount,
  bool requireForce = false,
}) {
  return showDialog<WorktreeDeleteResult>(
    context: context,
    builder: (_) => _WorktreeDeleteDialog(
      branchLabel: branchLabel,
      sessionCount: sessionCount,
      requireForce: requireForce,
    ),
  );
}

class _WorktreeDeleteDialog extends StatefulWidget {
  const _WorktreeDeleteDialog({
    required this.branchLabel,
    required this.sessionCount,
    required this.requireForce,
  });

  final String branchLabel;
  final int sessionCount;

  /// True when the worktree is dirty: force must be checked to confirm.
  final bool requireForce;

  @override
  State<_WorktreeDeleteDialog> createState() => _WorktreeDeleteDialogState();
}

class _WorktreeDeleteDialogState extends State<_WorktreeDeleteDialog> {
  bool _force = false;
  bool _deleteBranch = false;
  bool _deleteSessions = false;

  bool get _canConfirm => !widget.requireForce || _force;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.worktreeDeleteTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.worktreeDeleteBody(widget.branchLabel)),
            const SizedBox(height: 8),
            _check(
              value: _force,
              label: l10n.worktreeDeleteForce,
              onChanged: (v) => setState(() => _force = v),
            ),
            _check(
              value: _deleteBranch,
              label: l10n.worktreeDeleteBranchToo,
              onChanged: (v) => setState(() => _deleteBranch = v),
            ),
            if (widget.sessionCount > 0)
              _check(
                value: _deleteSessions,
                label: l10n.worktreeDeleteSessionsToo(widget.sessionCount),
                onChanged: (v) => setState(() => _deleteSessions = v),
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
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: _canConfirm
              ? () => Navigator.of(context).pop(WorktreeDeleteResult(
                  force: _force,
                  deleteBranch: _deleteBranch,
                  deleteSessions: _deleteSessions,
                ))
              : null,
          child: Text(l10n.worktreeDeleteAction),
        ),
      ],
    );
  }

  Widget _check({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(label),
      );
}
