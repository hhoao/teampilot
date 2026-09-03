import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/git/git_service.dart';
import '../../../services/git/worktree_branch_options.dart';
import '../../../services/git/worktree_create_result.dart';
import '../../../services/storage/runtime_context.dart';
import 'package:shared_ui/shared_ui.dart';

export '../../../services/git/worktree_branch_options.dart'
    show suggestWorktreeBranchName;

/// Loads branch choices for the existing-branch picker (local + remote-only).
typedef BranchListLoader =
    Future<List<WorktreeBranchOption>> Function(String repoPath);

/// Runs `git worktree add` (and any follow-up refresh) while the dialog shows
/// a submitting state. When omitted, the dialog pops with [WorktreeCreateResult]
/// immediately (used in tests and simple callers).
typedef WorktreeCreateSubmit =
    Future<void> Function(WorktreeCreateResult result);

/// Collects inputs for creating a git worktree. When [onSubmit] is set, the
/// dialog stays open with a progress affordance until it completes.
Future<WorktreeCreateResult?> showWorktreeCreateDialog(
  BuildContext context, {
  required String repoName,
  required String repoPath,
  required WorktreeLayoutPathResolver layout,
  required BranchListLoader branchLoader,
  List<String> existingWorktreePaths = const [],
  WorktreeCreateSubmit? onSubmit,
}) {
  return showDialog<WorktreeCreateResult>(
    context: context,
    barrierDismissible: onSubmit == null,
    builder: (_) => _WorktreeCreateDialog(
      repoName: repoName,
      repoPath: repoPath,
      layout: layout,
      branchLoader: branchLoader,
      existingWorktreePaths: existingWorktreePaths,
      onSubmit: onSubmit,
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
    required this.existingWorktreePaths,
    this.onSubmit,
  });

  final String repoName;
  final String repoPath;
  final WorktreeLayoutPathResolver layout;
  final BranchListLoader branchLoader;
  final List<String> existingWorktreePaths;
  final WorktreeCreateSubmit? onSubmit;

  @override
  State<_WorktreeCreateDialog> createState() => _WorktreeCreateDialogState();
}

class _WorktreeCreateDialogState extends State<_WorktreeCreateDialog> {
  final _formKey = GlobalKey<TpFormState>();
  final _branch = TextEditingController();
  String _selectorValue = '';
  List<WorktreeBranchOption> _branchOptions = const [];
  bool _loadingBranches = true;
  bool _submitting = false;
  String? _submitError;
  bool _nameUserEdited = false;
  String? _lastProgrammaticName;

  @override
  void initState() {
    super.initState();
    // Baseline: the controller's initial text is not a user edit; autofocus
    // selection notifications must not count as one.
    _lastProgrammaticName = _branch.text;
    _branch.addListener(() {
      if (_lastProgrammaticName != _branch.text) {
        _nameUserEdited = true;
      }
      setState(() {});
    });
    _loadBranches();
  }

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    try {
      final list = await widget.branchLoader(widget.repoPath);
      if (!mounted) return;
      setState(() {
        _branchOptions = list;
        _loadingBranches = false;
        if (_branch.text.trim().isEmpty && list.isNotEmpty) {
          _setBranchName(suggestWorktreeBranchName(list.first.name));
        }
      });
    } on Object {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  void _applyRandomName() {
    setState(() {
      _setBranchName(randomWorktreeBranchName(widget.existingWorktreePaths));
    });
  }

  /// Programmatic name write: tracked so [TextEditingController] notifications
  /// from it never count as a user edit.
  void _setBranchName(String name) {
    _lastProgrammaticName = name;
    _branch.text = name;
  }

  void _onSelectorChanged(String value) {
    setState(() {
      _selectorValue = value;
      final option = worktreeOptionForLabel(_branchOptions, value);
      if (option != null && !_nameUserEdited) {
        _setBranchName(option.name);
      }
    });
  }

  List<String> get _selectorItems =>
      [for (final option in _branchOptions) option.displayLabel];

  String get _previewPath => _branch.text.trim().isEmpty
      ? ''
      : widget.layout(
          repoName: widget.repoName,
          branch: _branch.text.trim(),
        );

  WorktreeCreateResult _buildResult() => buildWorktreeCreateResult(
    branch: _branch.text,
    selectorText: _selectorValue,
    options: _branchOptions,
    worktreePath: _previewPath,
  );

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = _buildResult();
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await onSubmit(result);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = context.l10n.worktreeCreateFailed(error.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final styles = TpTextStyles(theme);
    final inputsEnabled = !_submitting;
    return AlertDialog(
      title: Text(l10n.worktreeCreateTitle),
      content: SizedBox(
        width: 420,
        child: TpForm(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpInputFormField(
                key: const Key('worktree-branch-field'),
                controller: _branch,
                autofocus: true,
                enabled: inputsEnabled,
                decoration: InputDecoration(
                  labelText: l10n.worktreeBranchLabel,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingBranches)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      TpIconButton(
                        icon: Icons.casino_outlined,
                        size: TpIconButton.kCompactSize,
                        tooltip: l10n.worktreeRandomNameTooltip,
                        onTap: inputsEnabled ? _applyRandomName : null,
                      ),
                    ],
                  ),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? l10n.formFieldRequired
                        : null,
              ),
              const SizedBox(height: 12),
              IgnorePointer(
                ignoring: !inputsEnabled,
                child: Opacity(
                  opacity: inputsEnabled ? 1 : 0.5,
                  child: TpSelectWithCustomInput(
                    value: _selectorValue,
                    items: _selectorItems,
                    onChanged: _onSelectorChanged,
                    hintText: l10n.worktreeBaseSelectorHint,
                    decoration: TpSelectDecorations.themed(context),
                    customInputTooltip: l10n.worktreeBaseSelectorHint,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_previewPath.isNotEmpty) ...[
                Text(l10n.worktreePathLabel, style: styles.xs),
                const SizedBox(height: 2),
                Text(
                  _previewPath,
                  style: styles.sm,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
              if (_submitError case final error?) ...[
                Text(
                  error,
                  style: styles.smColored(theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: inputsEnabled ? () => Navigator.of(context).pop() : null,
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: inputsEnabled ? _submit : null,
          child: _submitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.worktreeCreating),
                  ],
                )
              : Text(l10n.worktreeCreateAction),
        ),
      ],
    );
  }
}
