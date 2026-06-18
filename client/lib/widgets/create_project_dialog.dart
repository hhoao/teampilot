import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../l10n/l10n_extensions.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';
import 'app_dialog.dart';

typedef CreateWorkspaceDraft = ({
  String primaryPath,
  List<String> additionalPaths,
  String display,
});

Future<CreateWorkspaceDraft?> showCreateWorkspaceDialog(BuildContext context) {
  return showDialog<CreateWorkspaceDraft>(
    context: context,
    builder: (ctx) => const _CreateWorkspaceDialog(),
  );
}

class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog();

  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  final _displayController = TextEditingController();
  String _primaryPath = '';
  final _additionalPaths = <String>[];

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  Future<void> _pickPrimary() async {
    final path = await pickWorkspaceDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _primaryPath = normalizeWorkspacePath(path));
  }

  Future<void> _addAdditional() async {
    final path = await pickWorkspaceDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final l10n = context.l10n;
    final trimmed = normalizeWorkspacePath(path);
    if (_primaryPath.isNotEmpty && workspacePathsEqual(trimmed, _primaryPath)) {
      AppToast.show(
        context,
        message: l10n.workspaceDirectoryAlreadyPrimary,
        variant: AppToastVariant.warning,
      );
      return;
    }
    if (workspacePathsContains(_additionalPaths, trimmed)) {
      AppToast.show(
        context,
        message: l10n.workspaceDirectoryAlreadyAdded,
        variant: AppToastVariant.warning,
      );
      return;
    }
    setState(() => _additionalPaths.add(trimmed));
  }

  void _create() {
    final l10n = context.l10n;
    if (_primaryPath.isEmpty) {
      AppToast.show(
        context,
        message: l10n.workspacePrimaryPathRequired,
        variant: AppToastVariant.error,
      );
      return;
    }
    Navigator.of(context).pop((
      primaryPath: _primaryPath,
      additionalPaths: List<String>.from(_additionalPaths),
      display: _displayController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return AppDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.newWorkspace),
          const SizedBox(height: 16),
          TextField(
                controller: _displayController,
                decoration: InputDecoration(labelText: l10n.workspaceDisplayName),
              ),
              const SizedBox(height: 16),
              Text(l10n.workspacePrimaryPath, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              if (_primaryPath.isEmpty)
                Text(
                  l10n.workspacePrimaryPathNotSelected,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                SelectableText(_primaryPath, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _pickPrimary,
                  icon: Icon(Icons.folder_open, size: context.appIconSizes.md),
                  label: Text(l10n.pickPrimaryDirectory),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.workspaceAdditionalDirectories,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (_additionalPaths.isEmpty)
                Text(
                  l10n.workspaceNoAdditionalDirectories,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ..._additionalPaths.map(
                  (path) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            path,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.removeWorkspaceDirectory,
                          icon: Icon(
                            Icons.remove_circle_outline,
                            size: context.appIconSizes.md,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () {
                            setState(() => _additionalPaths.remove(path));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addAdditional,
              icon: Icon(Icons.create_new_folder_outlined, size: context.appIconSizes.md),
              label: Text(l10n.addWorkspaceDirectory),
            ),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(onPressed: _create, child: Text(l10n.create)),
            ],
          ),
        ],
      ),
    );
  }
}
