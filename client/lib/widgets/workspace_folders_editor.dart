import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_topology.dart';
import '../services/storage/home_target_controller.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';

/// Edits a workspace's [WorkspaceFolder] list: per-row target + path.
///
/// Each row routes [pickWorkspaceDirectoryPath] by its own [targetId], enabling
/// local, project-remote, and mixed workspaces from one control.
class WorkspaceFoldersEditor extends StatefulWidget {
  const WorkspaceFoldersEditor({
    required this.folders,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<WorkspaceFolder> folders;
  final ValueChanged<List<WorkspaceFolder>> onChanged;
  final bool enabled;

  @override
  State<WorkspaceFoldersEditor> createState() => _WorkspaceFoldersEditorState();
}

class _WorkspaceFoldersEditorState extends State<WorkspaceFoldersEditor> {
  late List<WorkspaceFolder> _folders;
  Future<List<RuntimeTarget>>? _targets;

  @override
  void initState() {
    super.initState();
    _folders = List<WorkspaceFolder>.from(widget.folders);
    _targets = _loadTargets();
  }

  @override
  void didUpdateWidget(covariant WorkspaceFoldersEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folders != widget.folders) {
      _folders = List<WorkspaceFolder>.from(widget.folders);
    }
  }

  Future<List<RuntimeTarget>> _loadTargets() =>
      context.read<HomeTargetController>().listSelectable();

  void _emit(List<WorkspaceFolder> next) {
    setState(() => _folders = next);
    widget.onChanged(next);
  }

  Future<void> _pickPath(int index) async {
    if (!widget.enabled) return;
    final folder = _folders[index];
    final path = await pickWorkspaceDirectoryPath(
      context,
      targetId: folder.targetId,
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    final trimmed = normalizeWorkspacePath(path);
    final dup = _folders
        .asMap()
        .entries
        .any((e) => e.key != index && workspacePathsEqual(e.value.path, trimmed));
    if (dup) {
      AppToast.show(
        context,
        message: context.l10n.workspaceDirectoryAlreadyAdded,
        variant: AppToastVariant.warning,
      );
      return;
    }
    final next = [..._folders];
    next[index] = folder.copyWith(path: trimmed);
    _emit(next);
  }

  void _setTarget(int index, String targetId) {
    if (!widget.enabled) return;
    final next = [..._folders];
    next[index] = next[index].copyWith(targetId: targetId);
    _emit(next);
  }

  void _remove(int index) {
    if (!widget.enabled || _folders.length <= 1) return;
    _emit([..._folders]..removeAt(index));
  }

  Future<void> _addFolder() async {
    if (!widget.enabled) return;
    final targetId = _folders.isEmpty
        ? WorkspaceFolder.localTargetId
        : _folders.last.targetId;
    final path = await pickWorkspaceDirectoryPath(context, targetId: targetId);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final trimmed = normalizeWorkspacePath(path);
    if (workspacePathsContains(_folders.map((f) => f.path), trimmed)) return;
    _emit([
      ..._folders,
      WorkspaceFolder(path: trimmed, targetId: targetId),
    ]);
  }

  Future<void> _applyAllLocal() async {
    _emit([
      for (final f in _folders) f.copyWith(targetId: WorkspaceFolder.localTargetId),
    ]);
  }

  Future<void> _applyAllRemote() async {
    final targets = await (_targets ?? _loadTargets());
    if (!mounted) return;
    final remote = targets.where((t) => t.kind == RuntimeKind.ssh).toList();
    if (remote.isEmpty) return;
    final chosen = remote.length == 1
        ? remote.first
        : await showDialog<RuntimeTarget>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(context.l10n.workspaceFoldersPickRemoteTarget),
              children: [
                for (final t in remote)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, t),
                    child: Text('${t.label} (${t.id})'),
                  ),
              ],
            ),
          );
    if (chosen == null || !mounted) return;
    _emit([for (final f in _folders) f.copyWith(targetId: chosen.id)]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final topology = workspaceTopologyOf(_folders);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopologyChip(topology: topology),
        const SizedBox(height: 8),
        Text(
          l10n.workspaceFoldersEditorHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.enabled) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _applyAllLocal,
                child: Text(l10n.workspaceFoldersApplyAllLocal),
              ),
              OutlinedButton(
                onPressed: _applyAllRemote,
                child: Text(l10n.workspaceFoldersApplyAllRemote),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FutureBuilder<List<RuntimeTarget>>(
          future: _targets,
          builder: (context, snapshot) {
            final targets = snapshot.data ?? const <RuntimeTarget>[];
            return Column(
              children: [
                for (var i = 0; i < _folders.length; i++)
                  _FolderRow(
                    folder: _folders[i],
                    isPrimary: i == 0,
                    enabled: widget.enabled,
                    targets: targets,
                    onPickPath: () => _pickPath(i),
                    onTargetChanged: (id) => _setTarget(i, id),
                    onRemove: _folders.length > 1 ? () => _remove(i) : null,
                  ),
              ],
            );
          },
        ),
        if (widget.enabled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addFolder,
              icon: Icon(Icons.add, size: context.appIconSizes.md),
              label: Text(l10n.addWorkspaceDirectory),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopologyChip extends StatelessWidget {
  const _TopologyChip({required this.topology});

  final WorkspaceTopology topology;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, icon, color) = switch (topology) {
      WorkspaceTopology.local => (
        l10n.workspaceTopologyLocal,
        Icons.computer_outlined,
        Theme.of(context).colorScheme.primary,
      ),
      WorkspaceTopology.remote => (
        l10n.workspaceTopologyRemote,
        Icons.dns_outlined,
        Theme.of(context).colorScheme.tertiary,
      ),
      WorkspaceTopology.mixed => (
        l10n.workspaceTopologyMixed,
        Icons.hub_outlined,
        Theme.of(context).colorScheme.secondary,
      ),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.isPrimary,
    required this.enabled,
    required this.targets,
    required this.onPickPath,
    required this.onTargetChanged,
    required this.onRemove,
  });

  final WorkspaceFolder folder;
  final bool isPrimary;
  final bool enabled;
  final List<RuntimeTarget> targets;
  final VoidCallback onPickPath;
  final ValueChanged<String> onTargetChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final targetIds = targets.map((t) => t.id).toSet();
    final dropdownValue = targetIds.contains(folder.targetId)
        ? folder.targetId
        : folder.targetId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (isPrimary)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.star_rounded,
                      size: context.appIconSizes.sm,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: dropdownValue,
                    decoration: InputDecoration(
                      labelText: l10n.workspaceFolderTargetLabel,
                      isDense: true,
                    ),
                    items: [
                      for (final t in targets)
                        DropdownMenuItem(value: t.id, child: Text(t.label)),
                      if (!targetIds.contains(folder.targetId))
                        DropdownMenuItem(
                          value: folder.targetId,
                          child: Text(folder.targetId),
                        ),
                    ],
                    onChanged: enabled
                        ? (id) {
                            if (id != null) onTargetChanged(id);
                          }
                        : null,
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: l10n.removeWorkspaceDirectory,
                    icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                    onPressed: enabled ? onRemove : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    folder.path.isEmpty ? '—' : folder.path,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (enabled)
                  TextButton.icon(
                    onPressed: onPickPath,
                    icon: Icon(Icons.folder_open, size: context.appIconSizes.md),
                    label: Text(l10n.workspaceFoldersPickPath),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
