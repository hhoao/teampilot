import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/workspace_folder.dart';
import '../services/storage/home_target_controller.dart';
import '../theme/app_text_styles.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';
import 'settings/workspace_settings_widgets.dart';
import 'workspace_folder_directory_row.dart';

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
          f.targetId == widget.targetId && workspacePathsEqual(f.path, trimmed),
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
                for (var i = 0; i < widget.folders.length; i++)
                  WorkspaceFolderDirectoryRow(
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
