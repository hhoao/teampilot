import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/workspace.dart';
import '../models/workspace_folder.dart';
import '../repositories/session_repository.dart';
import 'app_dialog.dart';
import 'workspace_folders_editor.dart';

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
  late List<WorkspaceFolder> _folders;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.workspace.display);
    _folders = List<WorkspaceFolder>.from(widget.workspace.folders);
    if (_folders.isEmpty) {
      _folders = [const WorkspaceFolder(path: '')];
    }
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

  Future<void> _save() async {
    if (_saving) return;
    final valid = _folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    setState(() => _saving = true);
    final repo = context.read<SessionRepository>();
    final cubit = context.read<ChatCubit>();
    try {
      await repo.updateWorkspaceMetadata(
        widget.workspace.workspaceId,
        display: _displayController.text,
      );
      await repo.updateWorkspaceFolders(widget.workspace.workspaceId, valid);
      await cubit.loadWorkspaceData(repo);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = widget.workspace;

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
          Text(l10n.workspaceFoldersSectionTitle, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          WorkspaceFoldersEditor(
            folders: _folders,
            enabled: !_saving,
            onChanged: (next) => setState(() => _folders = next),
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
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
