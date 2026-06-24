import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_topology.dart';
import '../services/storage/home_target_controller.dart';
import '../theme/app_text_styles.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';
import 'settings/workspace_settings_widgets.dart';

/// Compact directory picker for the "new workspace" dialogs: pick a machine,
/// add folders cumulatively (each row keeps its own [WorkspaceFolder.targetId]),
/// then [workspaceTopologyOf] classifies the draft at create time.
class WorkspaceCreateDirectoryPicker extends StatefulWidget {
  const WorkspaceCreateDirectoryPicker({
    super.key,
    required this.targetId,
    required this.onTargetChanged,
    required this.folders,
    required this.onFoldersChanged,
  });

  final String targetId;
  final ValueChanged<String> onTargetChanged;
  final List<WorkspaceFolder> folders;
  final ValueChanged<List<WorkspaceFolder>> onFoldersChanged;

  @override
  State<WorkspaceCreateDirectoryPicker> createState() =>
      _WorkspaceCreateDirectoryPickerState();
}

class _WorkspaceCreateDirectoryPickerState
    extends State<WorkspaceCreateDirectoryPicker> {
  late Future<List<RuntimeTarget>> _targets;

  @override
  void initState() {
    super.initState();
    _targets = _loadTargets();
  }

  Future<List<RuntimeTarget>> _loadTargets() =>
      context.read<HomeTargetController>().listSelectable();

  Future<void> _addDirectory() async {
    final picked = await pickWorkspaceDirectoryPath(
      context,
      targetId: widget.targetId,
    );
    final trimmed = picked?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    final duplicate = widget.folders.any(
      (f) =>
          f.targetId == widget.targetId &&
          workspacePathsEqual(f.path, trimmed),
    );
    if (duplicate) return;
    widget.onFoldersChanged([
      ...widget.folders,
      WorkspaceFolder(path: trimmed, targetId: widget.targetId),
    ]);
  }

  void _removeDirectoryAt(int index) {
    widget.onFoldersChanged([
      ...widget.folders.sublist(0, index),
      ...widget.folders.sublist(index + 1),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final hasDirectory = widget.folders.isNotEmpty;

    return FutureBuilder<List<RuntimeTarget>>(
      future: _targets,
      builder: (context, snapshot) {
        final targets = snapshot.data ?? const <RuntimeTarget>[];
        final targetIds = targets.map((t) => t.id).toSet();
        final entries = <(String, String)>[
          for (final t in targets) (t.id, t.label),
          if (!targetIds.contains(widget.targetId))
            (widget.targetId, widget.targetId),
        ];

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasDirectory
                  ? cs.primary.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary,
                          Color.lerp(cs.primary, cs.tertiary, 0.6) ??
                              cs.primary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_open_rounded,
                      size: context.appIconSizes.lg,
                      color: cs.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.homeWorkspaceNewWorkspaceDirectoryLabel,
                      style: styles.bodyStrong.copyWith(color: cs.onSurface),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SettingsCompactDropdown<String>(
                    value: widget.targetId,
                    entries: entries,
                    onChanged: (id) {
                      if (id == null || id == widget.targetId) return;
                      widget.onTargetChanged(id);
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _addDirectory,
                    icon: Icon(
                      Icons.drive_folder_upload_outlined,
                      size: context.appIconSizes.md,
                    ),
                    label: Text(l10n.homeWorkspaceNewWorkspaceChooseDirectory),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hasDirectory) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 58),
                  child: Text(
                    l10n.homeWorkspaceNewWorkspaceDirectoryHint,
                    style: styles.body.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 58, top: 4),
                  child: _TopologyChip(
                    topology: workspaceTopologyOf(widget.folders),
                  ),
                ),
                for (var i = 0; i < widget.folders.length; i++)
                  _DirectoryRow(
                    folder: widget.folders[i],
                    isPrimary: i == 0,
                    targets: targets,
                    onRemove: () => _removeDirectoryAt(i),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TopologyChip extends StatelessWidget {
  const _TopologyChip({required this.topology});

  final WorkspaceTopology topology;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (topology) {
      WorkspaceTopology.local => (
        l10n.workspaceTopologyLocal,
        Icons.computer_outlined,
        cs.primary,
      ),
      WorkspaceTopology.remote => (
        l10n.workspaceTopologyRemote,
        Icons.dns_outlined,
        cs.tertiary,
      ),
      WorkspaceTopology.mixed => (
        l10n.workspaceTopologyMixed,
        Icons.hub_outlined,
        cs.secondary,
      ),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: Theme.of(context).textTheme.labelSmall),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.folder,
    required this.isPrimary,
    required this.targets,
    required this.onRemove,
  });

  final WorkspaceFolder folder;
  final bool isPrimary;
  final List<RuntimeTarget> targets;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final path = folder.path;
    final name = _workspacePathBasename(path);
    final parent = _workspacePathParent(path);
    final targetLabel = _targetLabel(targets, folder.targetId);
    final targetKind = runtimeKindOfId(folder.targetId);

    return Padding(
      padding: const EdgeInsets.only(left: 58, top: 8),
      child: Tooltip(
        message: '$path\n${l10n.workspaceFolderTargetLabel}: $targetLabel',
        child: Row(
          children: [
            Icon(
              isPrimary
                  ? Icons.star_rounded
                  : Icons.subdirectory_arrow_right_rounded,
              size: context.appIconSizes.sm,
              color: isPrimary ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: _pathLabel(name, parent, styles, cs)),
            const SizedBox(width: 10),
            Icon(
              switch (targetKind) {
                RuntimeKind.ssh => Icons.dns_outlined,
                RuntimeKind.wsl => Icons.terminal_outlined,
                RuntimeKind.local => Icons.computer_outlined,
              },
              size: context.appIconSizes.sm,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                targetLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: styles.caption.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: l10n.removeWorkspaceDirectory,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.close_rounded,
                size: context.appIconSizes.sm,
                color: cs.onSurfaceVariant,
              ),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  static String _targetLabel(List<RuntimeTarget> targets, String targetId) {
    for (final t in targets) {
      if (t.id == targetId) return t.label;
    }
    if (targetId == WorkspaceFolder.localTargetId) {
      return RuntimeTarget.local().label;
    }
    return targetId;
  }

  static Widget _pathLabel(
    String name,
    String parent,
    AppTextStyles styles,
    ColorScheme cs,
  ) {
    final title = styles.body.copyWith(color: cs.onSurface);
    final detail = styles.caption.copyWith(color: cs.onSurfaceVariant);
    if (parent.isEmpty) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: title.copyWith(fontWeight: FontWeight.w600),
      );
    }
    return Text.rich(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      TextSpan(
        children: [
          TextSpan(
            text: name,
            style: title.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' · ', style: detail),
          TextSpan(text: parent, style: detail),
        ],
      ),
    );
  }
}

String _workspacePathBasename(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('~')) {
    final parts = trimmed.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? trimmed : parts.last;
  }
  final ctx = trimmed.startsWith('/') && !trimmed.startsWith('//')
      ? p.Context(style: p.Style.posix)
      : p.context;
  final base = ctx.basename(trimmed);
  return base.isEmpty ? trimmed : base;
}

String _workspacePathParent(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('~')) {
    final parts = trimmed.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length <= 1) {
      return trimmed == '~' || trimmed.startsWith('~/') ? '~' : trimmed;
    }
    return '~/${parts.sublist(0, parts.length - 1).join('/')}';
  }
  final ctx = trimmed.startsWith('/') && !trimmed.startsWith('//')
      ? p.Context(style: p.Style.posix)
      : p.context;
  final parent = ctx.dirname(trimmed);
  if (parent == trimmed || parent == '.' || parent.isEmpty) return '';
  return parent;
}

class WorkspaceCreateNameField extends StatelessWidget {
  const WorkspaceCreateNameField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.workspaceDisplayName,
            style: styles.caption.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onSubmitted: onSubmitted,
            style: styles.prominent.copyWith(color: cs.onSurface),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}
