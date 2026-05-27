import 'package:flutter/material.dart';

import '../l10n/l10n_extensions.dart';
import '../utils/project_path_picker.dart';
import '../utils/project_path_utils.dart';

typedef CreateProjectDraft = ({
  String primaryPath,
  List<String> additionalPaths,
  String display,
});

Future<CreateProjectDraft?> showCreateProjectDialog(BuildContext context) {
  return showDialog<CreateProjectDraft>(
    context: context,
    builder: (ctx) => const _CreateProjectDialog(),
  );
}

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _displayController = TextEditingController();
  String _primaryPath = '';
  final _additionalPaths = <String>[];

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  Future<void> _pickPrimary() async {
    final path = await pickProjectDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _primaryPath = normalizeProjectPath(path));
  }

  Future<void> _addAdditional() async {
    final path = await pickProjectDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final l10n = context.l10n;
    final trimmed = normalizeProjectPath(path);
    if (_primaryPath.isNotEmpty && projectPathsEqual(trimmed, _primaryPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectDirectoryAlreadyPrimary)),
      );
      return;
    }
    if (projectPathsContains(_additionalPaths, trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectDirectoryAlreadyAdded)),
      );
      return;
    }
    setState(() => _additionalPaths.add(trimmed));
  }

  void _create() {
    final l10n = context.l10n;
    if (_primaryPath.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.projectPrimaryPathRequired)));
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

    return AlertDialog(
      title: Text(l10n.newProject),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _displayController,
                decoration: InputDecoration(labelText: l10n.projectDisplayName),
              ),
              const SizedBox(height: 16),
              Text(l10n.projectPrimaryPath, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              if (_primaryPath.isEmpty)
                Text(
                  l10n.projectPrimaryPathNotSelected,
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
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(l10n.pickPrimaryDirectory),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.projectAdditionalDirectories,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              if (_additionalPaths.isEmpty)
                Text(
                  l10n.projectNoAdditionalDirectories,
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
                          tooltip: l10n.removeProjectDirectory,
                          icon: Icon(
                            Icons.remove_circle_outline,
                            size: 18,
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
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(l10n.addProjectDirectory),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _create, child: Text(l10n.create)),
      ],
    );
  }
}
