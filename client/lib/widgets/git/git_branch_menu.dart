import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';

/// Result of the branch picker: switch to [checkout] or create [createName].
class GitBranchAction {
  const GitBranchAction.checkout(this.checkout) : createName = null;
  const GitBranchAction.create(this.createName) : checkout = null;

  final String? checkout;
  final String? createName;
}

/// Bottom-sheet branch picker: lists local branches and offers "new branch".
class GitBranchSheet extends StatefulWidget {
  const GitBranchSheet({
    required this.branches,
    required this.current,
    super.key,
  });

  final List<String> branches;
  final String? current;

  static Future<GitBranchAction?> show(
    BuildContext context, {
    required List<String> branches,
    required String? current,
  }) {
    return showModalBottomSheet<GitBranchAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => GitBranchSheet(branches: branches, current: current),
    );
  }

  @override
  State<GitBranchSheet> createState() => _GitBranchSheetState();
}

class _GitBranchSheetState extends State<GitBranchSheet> {
  final _newBranchController = TextEditingController();
  var _creating = false;

  @override
  void dispose() {
    _newBranchController.dispose();
    super.dispose();
  }

  void _submitCreate() {
    final name = _newBranchController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(GitBranchAction.create(name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                l10n.gitSwitchBranch,
                style: AppTextStyles.of(context).body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final branch in widget.branches)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        branch == widget.current
                            ? Icons.check
                            : Icons.commit_outlined,
                        size: 18,
                        color: branch == widget.current
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      title: Text(branch),
                      onTap: branch == widget.current
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(GitBranchAction.checkout(branch)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_creating)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newBranchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l10n.gitNewBranchHint,
                        ),
                        onSubmitted: (_) => _submitCreate(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitCreate,
                      child: Text(l10n.gitCreateBranch),
                    ),
                  ],
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.add, size: 18),
                title: Text(l10n.gitCreateBranch),
                onTap: () => setState(() => _creating = true),
              ),
          ],
        ),
      ),
    );
  }
}
