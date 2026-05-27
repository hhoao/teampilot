import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_project.dart';
import '../repositories/session_repository.dart';
import '../utils/project_path_picker.dart';
import '../utils/project_path_utils.dart';

Future<void> showProjectDetailsDialog(
  BuildContext context,
  AppProject project,
  int sessionCount,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) =>
        _ProjectDetailsDialog(project: project, sessionCount: sessionCount),
  );
}

class _ProjectDetailsDialog extends StatefulWidget {
  const _ProjectDetailsDialog({
    required this.project,
    required this.sessionCount,
  });

  final AppProject project;
  final int sessionCount;

  @override
  State<_ProjectDetailsDialog> createState() => _ProjectDetailsDialogState();
}

class _ProjectDetailsDialogState extends State<_ProjectDetailsDialog> {
  late final TextEditingController _displayController;
  late List<String> _additionalPaths;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.project.display);
    _additionalPaths = List<String>.from(widget.project.additionalPaths);
  }

  @override
  void dispose() {
    _displayController.dispose();
    super.dispose();
  }

  String _formatTimestamp(int ms) {
    if (ms <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.pathCopied(path)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addDirectory() async {
    final path = await pickProjectDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final trimmed = normalizeProjectPath(path);
    final l10n = context.l10n;
    if (projectPathsEqual(trimmed, widget.project.primaryPath)) {
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
    setState(() => _additionalPaths = [..._additionalPaths, trimmed]);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<SessionRepository>();
    final cubit = context.read<ChatCubit>();
    try {
      await cubit.updateProjectMetadata(
        repo,
        widget.project.projectId,
        display: _displayController.text,
        additionalPaths: _additionalPaths,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = widget.project;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.projectDetailsTitle),
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
              _DetailRow(
                label: l10n.projectPrimaryPath,
                value: p.primaryPath.isNotEmpty ? p.primaryPath : '—',
                onCopy: p.primaryPath.isNotEmpty
                    ? () => _copyPath(p.primaryPath)
                    : null,
              ),
              const SizedBox(height: 12),
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
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            path,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.copyFolderPath,
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copyPath(path),
                        ),
                        IconButton(
                          tooltip: l10n.removeProjectDirectory,
                          icon: Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                            color: theme.colorScheme.error,
                          ),
                          onPressed: () {
                            setState(
                              () => _additionalPaths = _additionalPaths
                                  .where((e) => e != path)
                                  .toList(),
                            );
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
                  onPressed: _saving ? null : _addDirectory,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(l10n.addProjectDirectory),
                ),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                label: l10n.projectSessionCount,
                value: '${widget.sessionCount}',
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: l10n.projectCreatedAt,
                value: _formatTimestamp(p.createdAt),
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: l10n.projectUpdatedAt,
                value: _formatTimestamp(p.updatedAt),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(value, style: theme.textTheme.bodyMedium),
            ),
            if (onCopy != null)
              IconButton(
                tooltip: context.l10n.copyFolderPath,
                icon: const Icon(Icons.copy, size: 18),
                onPressed: onCopy,
              ),
          ],
        ),
      ],
    );
  }
}
