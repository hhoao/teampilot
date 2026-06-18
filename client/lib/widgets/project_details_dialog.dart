import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_workspace.dart';
import '../repositories/session_repository.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';
import 'app_dialog.dart';

Future<void> showWorkspaceDetailsDialog(
  BuildContext context,
  Workspace workspace,
  int sessionCount,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) =>
        _WorkspaceDetailsDialog(workspace: workspace, sessionCount: sessionCount),
  );
}

class _WorkspaceDetailsDialog extends StatefulWidget {
  const _WorkspaceDetailsDialog({
    required this.workspace,
    required this.sessionCount,
  });

  final Workspace workspace;
  final int sessionCount;

  @override
  State<_WorkspaceDetailsDialog> createState() => _WorkspaceDetailsDialogState();
}

class _WorkspaceDetailsDialogState extends State<_WorkspaceDetailsDialog> {
  late final TextEditingController _displayController;
  late List<String> _additionalPaths;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.workspace.display);
    _additionalPaths = List<String>.from(widget.workspace.additionalPaths);
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
    AppToast.show(
      context,
      message: l10n.pathCopied(path),
      variant: AppToastVariant.success,
    );
  }

  Future<void> _addDirectory() async {
    final path = await pickWorkspaceDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final trimmed = normalizeWorkspacePath(path);
    final l10n = context.l10n;
    if (workspacePathsEqual(trimmed, widget.workspace.primaryPath)) {
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
    setState(() => _additionalPaths = [..._additionalPaths, trimmed]);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = context.read<SessionRepository>();
    final cubit = context.read<ChatCubit>();
    try {
      await cubit.updateWorkspaceMetadata(
        repo,
        widget.workspace.workspaceId,
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
    final p = widget.workspace;
    final theme = Theme.of(context);

    return AppDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.workspaceDetailsTitle),
          const SizedBox(height: 16),
          TextField(
                controller: _displayController,
                decoration: InputDecoration(labelText: l10n.workspaceDisplayName),
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: l10n.workspacePrimaryPath,
                value: p.primaryPath.isNotEmpty ? p.primaryPath : '—',
                onCopy: p.primaryPath.isNotEmpty
                    ? () => _copyPath(p.primaryPath)
                    : null,
              ),
              const SizedBox(height: 12),
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
                          icon: Icon(Icons.copy, size: context.appIconSizes.md),
                          onPressed: () => _copyPath(path),
                        ),
                        IconButton(
                          tooltip: l10n.removeWorkspaceDirectory,
                          icon: Icon(
                            Icons.remove_circle_outline,
                            size: context.appIconSizes.md,
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
                  icon: Icon(Icons.create_new_folder_outlined, size: context.appIconSizes.md),
                  label: Text(l10n.addWorkspaceDirectory),
                ),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                label: l10n.workspaceSessionCount,
                value: '${widget.sessionCount}',
              ),
              const SizedBox(height: 8),
              _DetailRow(
                label: l10n.workspaceCreatedAt,
                value: _formatTimestamp(p.createdAt),
              ),
              const SizedBox(height: 8),
          _DetailRow(
            label: l10n.workspaceUpdatedAt,
            value: _formatTimestamp(p.updatedAt),
          ),
          AppDialogActions(
            children: [
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
          ),
        ],
      ),
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
                icon: Icon(Icons.copy, size: context.appIconSizes.md),
                onPressed: onCopy,
              ),
          ],
        ),
      ],
    );
  }
}
