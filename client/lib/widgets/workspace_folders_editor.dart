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
import '../theme/app_text_styles.dart';
import '../utils/workspace_path_picker.dart';
import '../utils/workspace_path_utils.dart';
import 'workspace_folder_directory_row.dart';

/// Hint copy for the workspace folders settings section.
String workspaceFoldersEditorHint(
  AppLocalizations l10n,
  List<WorkspaceFolder> folders, {
  required bool lockTargets,
}) {
  final topology = workspaceTopologyOf(folders);
  if (topology == WorkspaceTopology.mixed) {
    return l10n.workspaceFoldersMixedTargetsLockedHint;
  }
  if (lockTargets) {
    return l10n.workspaceFoldersPersonalTargetsLockedHint;
  }
  return l10n.workspaceFoldersEditorHint;
}

/// Edits a workspace's [WorkspaceFolder] list grouped by machine.
class WorkspaceFoldersEditor extends StatefulWidget {
  const WorkspaceFoldersEditor({
    required this.folders,
    required this.onChanged,
    this.enabled = true,
    this.lockTargets = false,
    super.key,
  });

  final List<WorkspaceFolder> folders;
  final ValueChanged<List<WorkspaceFolder>> onChanged;
  final bool enabled;

  /// When true, folder [targetId] is read-only (e.g. personal launch identity).
  final bool lockTargets;

  @override
  State<WorkspaceFoldersEditor> createState() => _WorkspaceFoldersEditorState();
}

class _FolderGroupEntry {
  const _FolderGroupEntry({required this.index, required this.folder});

  final int index;
  final WorkspaceFolder folder;
}

class _TargetFolderGroup {
  const _TargetFolderGroup({
    required this.targetId,
    required this.entries,
  });

  final String targetId;
  final List<_FolderGroupEntry> entries;
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

  List<_TargetFolderGroup> _groupFolders() {
    final order = <String>[];
    final byTarget = <String, List<_FolderGroupEntry>>{};
    for (var i = 0; i < _folders.length; i++) {
      final folder = _folders[i];
      byTarget.putIfAbsent(folder.targetId, () => []).add(
        _FolderGroupEntry(index: i, folder: folder),
      );
      if (!order.contains(folder.targetId)) {
        order.add(folder.targetId);
      }
    }
    return [
      for (final targetId in order)
        _TargetFolderGroup(
          targetId: targetId,
          entries: byTarget[targetId]!,
        ),
    ];
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
        .any(
          (e) =>
              e.key != index &&
              e.value.targetId == folder.targetId &&
              workspacePathsEqual(e.value.path, trimmed),
        );
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

  void _setTargetForGroup(String targetId, String newTargetId) {
    if (!widget.enabled || _targetsLocked || targetId == newTargetId) return;
    _emit([
      for (final f in _folders)
        f.targetId == targetId ? f.copyWith(targetId: newTargetId) : f,
    ]);
  }

  void _setTargetForRow(int index, String targetId) {
    if (!widget.enabled || _targetsLocked) return;
    final next = [..._folders];
    next[index] = next[index].copyWith(targetId: targetId);
    _emit(next);
  }

  Future<void> _pickTargetForGroup(String targetId) async {
    if (!widget.enabled || _targetsLocked) return;
    final chosen = await _pickTargetDialog(current: targetId);
    if (chosen != null) {
      _setTargetForGroup(targetId, chosen);
    }
  }

  Future<void> _pickTargetForRow(int index) async {
    if (!widget.enabled || _targetsLocked) return;
    final current = _folders[index].targetId;
    final chosen = await _pickTargetDialog(current: current);
    if (chosen != null && chosen != current) {
      _setTargetForRow(index, chosen);
    }
  }

  Future<String?> _pickTargetDialog({required String current}) async {
    final targets = await (_targets ?? _loadTargets());
    if (!mounted) return null;
    final targetIds = targets.map((t) => t.id).toSet();
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.l10n.workspaceFoldersPickTarget),
        children: [
          for (final t in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t.id),
              child: Row(
                children: [
                  Icon(
                    t.kind == RuntimeKind.ssh
                        ? Icons.cloud_outlined
                        : Icons.computer_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.label)),
                ],
              ),
            ),
          if (!targetIds.contains(current))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, current),
              child: Text(current),
            ),
        ],
      ),
    );
  }

  Future<void> _addFolderOnTarget(String targetId) async {
    if (!widget.enabled) return;
    final path = await pickWorkspaceDirectoryPath(context, targetId: targetId);
    if (path == null || path.trim().isEmpty || !mounted) return;
    final trimmed = normalizeWorkspacePath(path);
    if (_folders.any(
      (f) =>
          f.targetId == targetId && workspacePathsEqual(f.path, trimmed),
    )) {
      return;
    }
    _emit([
      ..._folders,
      WorkspaceFolder(path: trimmed, targetId: targetId),
    ]);
  }

  Future<void> _addFolderOnAnotherMachine() async {
    if (!widget.enabled || _targetsLocked) return;
    final targets = await (_targets ?? _loadTargets());
    if (!mounted) return;
    final used = workspaceTargetIds(_folders).toSet();
    final candidates = targets.where((t) => !used.contains(t.id)).toList();
    if (candidates.isEmpty) return;
    final chosen = candidates.length == 1
        ? candidates.first
        : await showDialog<RuntimeTarget>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: Text(context.l10n.workspaceFoldersPickTarget),
              children: [
                for (final t in candidates)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, t),
                    child: Text(t.label),
                  ),
              ],
            ),
          );
    if (chosen == null || !mounted) return;
    await _addFolderOnTarget(chosen.id);
  }

  Future<void> _applyAllLocal() async {
    if (_targetsLocked) return;
    _emit([
      for (final f in _folders)
        f.copyWith(targetId: WorkspaceFolder.localTargetId),
    ]);
  }

  Future<void> _applyAllRemote() async {
    if (_targetsLocked) return;
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

  bool get _targetsLocked =>
      widget.lockTargets ||
      workspaceTopologyOf(_folders) == WorkspaceTopology.mixed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lockTargets = _targetsLocked;
    final groups = _groupFolders();
    final hasDirectory = _folders.any((f) => f.path.trim().isNotEmpty);
    const primaryIndex = 0;

    return FutureBuilder<List<RuntimeTarget>>(
      future: _targets,
      builder: (context, snapshot) {
        final targets = snapshot.data ?? const <RuntimeTarget>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.enabled && !lockTargets) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _applyAllLocal,
                    child: Text(l10n.workspaceFoldersApplyAllLocal),
                  ),
                  OutlinedButton(
                    onPressed: _applyAllRemote,
                    child: Text(l10n.workspaceFoldersApplyAllRemote),
                  ),
                  if (groups.length == 1)
                    OutlinedButton.icon(
                      onPressed: _addFolderOnAnotherMachine,
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: context.appIconSizes.md,
                      ),
                      label: Text(l10n.workspaceFoldersAddOnAnotherMachine),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
              if (!hasDirectory && groups.length == 1)
              _MachineFolderCard(
                targetId: groups.first.targetId,
                targetLabel: workspaceFolderTargetLabel(
                  targets,
                  groups.first.targetId,
                ),
                entries: groups.first.entries,
                targets: targets,
                primaryIndex: primaryIndex,
                enabled: widget.enabled,
                targetEditable: !lockTargets,
                allowRowTargetChange: !lockTargets,
                onPickTargetForGroup: () =>
                    _pickTargetForGroup(groups.first.targetId),
                onAddDirectory: () =>
                    _addFolderOnTarget(groups.first.targetId),
                onPickPath: _pickPath,
                onPickTargetForRow: _pickTargetForRow,
                emptyHint: l10n.homeWorkspaceNewWorkspaceDirectoryHint,
              )
            else
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MachineFolderCard(
                    targetId: group.targetId,
                    targetLabel: workspaceFolderTargetLabel(
                      targets,
                      group.targetId,
                    ),
                    entries: group.entries,
                    targets: targets,
                    primaryIndex: primaryIndex,
                    enabled: widget.enabled,
                    targetEditable: !lockTargets,
                    allowRowTargetChange:
                        !lockTargets &&
                        workspaceTopologyOf(_folders) !=
                            WorkspaceTopology.mixed,
                    onPickTargetForGroup: () =>
                        _pickTargetForGroup(group.targetId),
                    onAddDirectory: () => _addFolderOnTarget(group.targetId),
                    onPickPath: _pickPath,
                    onPickTargetForRow: _pickTargetForRow,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _MachineFolderCard extends StatelessWidget {
  const _MachineFolderCard({
    required this.targetId,
    required this.targetLabel,
    required this.entries,
    required this.targets,
    required this.primaryIndex,
    required this.enabled,
    required this.targetEditable,
    required this.allowRowTargetChange,
    required this.onPickTargetForGroup,
    required this.onAddDirectory,
    required this.onPickPath,
    required this.onPickTargetForRow,
    this.emptyHint,
  });

  final String targetId;
  final String targetLabel;
  final List<_FolderGroupEntry> entries;
  final List<RuntimeTarget> targets;
  final int primaryIndex;
  final bool enabled;
  final bool targetEditable;
  final bool allowRowTargetChange;
  final VoidCallback onPickTargetForGroup;
  final VoidCallback onAddDirectory;
  final ValueChanged<int> onPickPath;
  final ValueChanged<int> onPickTargetForRow;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final listed = entries.where((e) => e.folder.path.trim().isNotEmpty).toList();
    final showEmptyHint = listed.isEmpty && emptyHint != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  workspaceFolderTargetIcon(targetId),
                  size: context.appIconSizes.md,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    targetLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.bodyStrong.copyWith(color: cs.onSurface),
                  ),
                ),
                if (targetEditable && enabled)
                  TextButton(
                    onPressed: onPickTargetForGroup,
                    child: Text(l10n.workspaceFoldersChangeTarget),
                  ),
                if (enabled)
                  TextButton.icon(
                    onPressed: onAddDirectory,
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      size: context.appIconSizes.sm,
                    ),
                    label: Text(l10n.addWorkspaceDirectory),
                  ),
              ],
            ),
            if (showEmptyHint)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  emptyHint!,
                  style: styles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              )
            else if (listed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  children: [
                    for (final entry in listed)
                      WorkspaceFolderDirectoryRow(
                        folder: entry.folder,
                        isPrimary: entry.index == primaryIndex,
                        targets: targets,
                        showTarget: false,
                        contentIndent: 0,
                        onPickPath:
                            enabled ? () => onPickPath(entry.index) : null,
                        onPickTarget: enabled && allowRowTargetChange
                            ? () => onPickTargetForRow(entry.index)
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
