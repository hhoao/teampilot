import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/l10n_extensions.dart';
import '../models/app_workspace.dart';
import '../models/workspace_icon_picker_result.dart';
import '../models/workspace_icon_ref.dart';
import '../utils/workspace_geometry_catalog.dart';
import 'app_dialog.dart';
import 'workspace_icon.dart';

/// Pure UI for choosing a bundled icon; orchestration lives in [ChatCubit].
Future<WorkspaceIconPickerResult> showWorkspaceIconPickerDialog(
  BuildContext context, {
  required Workspace workspace,
}) {
  final l10n = context.l10n;
  return showDialog<WorkspaceIconPickerResult>(
    context: context,
    builder: (ctx) => _WorkspaceIconPickerDialog(
      workspace: workspace,
      title: l10n.workspaceIconPickerTitle,
      useDefaultLabel: l10n.workspaceIconUseDefault,
      uploadLabel: l10n.workspaceIconUpload,
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    ),
  ).then((value) => value ?? const WorkspaceIconPickerCancelled());
}

class _WorkspaceIconPickerDialog extends StatefulWidget {
  const _WorkspaceIconPickerDialog({
    required this.workspace,
    required this.title,
    required this.useDefaultLabel,
    required this.uploadLabel,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final Workspace workspace;
  final String title;
  final String useDefaultLabel;
  final String uploadLabel;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_WorkspaceIconPickerDialog> createState() =>
      _WorkspaceIconPickerDialogState();
}

class _WorkspaceIconPickerDialogState extends State<_WorkspaceIconPickerDialog> {
  late WorkspaceIconRef _draftIcon;

  @override
  void initState() {
    super.initState();
    _draftIcon = widget.workspace.icon;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppDialogHeader(title: widget.title),
          const SizedBox(height: 16),
          WorkspaceIcon.fromWorkspace(
              widget.workspace,
              previewIcon: _draftIcon,
              size: 72,
              padding: 12,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text(widget.useDefaultLabel),
                    selected: _draftIcon is WorkspaceIconAuto,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _draftIcon = WorkspaceIconRef.auto);
                    },
                  ),
                  ActionChip(
                    avatar: Icon(
                      Icons.upload_file_outlined,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    label: Text(widget.uploadLabel),
                    onPressed: () => Navigator.of(context).pop(
                      const WorkspaceIconPickerUploadRequested(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: kWorkspaceGeometryIconAssets.length,
              itemBuilder: (context, index) {
                final selected = _draftIcon is WorkspaceIconPreset &&
                    (_draftIcon as WorkspaceIconPreset).index == index;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _draftIcon = WorkspaceIconPreset(index));
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.35),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: SvgPicture.asset(
                      kWorkspaceGeometryIconAssets[index],
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(
                  const WorkspaceIconPickerCancelled(),
                ),
                child: Text(widget.cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  WorkspaceIconPickerCommitted(_draftIcon),
                ),
                child: Text(widget.saveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
