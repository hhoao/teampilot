import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/l10n_extensions.dart';
import '../models/app_project.dart';
import '../models/project_icon_picker_result.dart';
import '../models/project_icon_ref.dart';
import '../utils/project_geometry_catalog.dart';
import 'app_dialog.dart';
import 'project_icon.dart';

/// Pure UI for choosing a bundled icon; orchestration lives in [ChatCubit].
Future<ProjectIconPickerResult> showProjectIconPickerDialog(
  BuildContext context, {
  required AppProject project,
}) {
  final l10n = context.l10n;
  return showDialog<ProjectIconPickerResult>(
    context: context,
    builder: (ctx) => _ProjectIconPickerDialog(
      project: project,
      title: l10n.projectIconPickerTitle,
      useDefaultLabel: l10n.projectIconUseDefault,
      uploadLabel: l10n.projectIconUpload,
      cancelLabel: l10n.cancel,
      saveLabel: l10n.save,
    ),
  ).then((value) => value ?? const ProjectIconPickerCancelled());
}

class _ProjectIconPickerDialog extends StatefulWidget {
  const _ProjectIconPickerDialog({
    required this.project,
    required this.title,
    required this.useDefaultLabel,
    required this.uploadLabel,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final AppProject project;
  final String title;
  final String useDefaultLabel;
  final String uploadLabel;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_ProjectIconPickerDialog> createState() =>
      _ProjectIconPickerDialogState();
}

class _ProjectIconPickerDialogState extends State<_ProjectIconPickerDialog> {
  late ProjectIconRef _draftIcon;

  @override
  void initState() {
    super.initState();
    _draftIcon = widget.project.icon;
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
          ProjectIcon.fromProject(
              widget.project,
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
                    selected: _draftIcon is ProjectIconAuto,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _draftIcon = ProjectIconRef.auto);
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
                      const ProjectIconPickerUploadRequested(),
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
              itemCount: kProjectGeometryIconAssets.length,
              itemBuilder: (context, index) {
                final selected = _draftIcon is ProjectIconPreset &&
                    (_draftIcon as ProjectIconPreset).index == index;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => _draftIcon = ProjectIconPreset(index));
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
                      kProjectGeometryIconAssets[index],
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
                  const ProjectIconPickerCancelled(),
                ),
                child: Text(widget.cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  ProjectIconPickerCommitted(_draftIcon),
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
