import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../repositories/session_repository.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/project_display_name.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/project_details_dialog.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import 'project_icon_settings_row.dart';

/// Project basic settings + danger zone (same layout as [TeamInfoSection]).
class ProjectInfoSection extends StatelessWidget {
  const ProjectInfoSection({required this.project, super.key});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = context.select<ChatCubit, AppProject>(
      (c) => c.state.projects.firstWhere(
        (p) => p.projectId == project.projectId,
        orElse: () => project,
      ),
    );
    final sessionCount = context.select<ChatCubit, int>(
      (c) => c.state.sessions
          .where((s) => s.projectId == live.projectId)
          .length,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupHeader(
                  title: l10n.homeWorkspaceProjectSettingsBasicInfo,
                ),
                ProjectIconSettingsRow(project: live),
                _ProjectSettingsInlineRow(
                  label: l10n.projectDisplayName,
                  value: live.localizedName(l10n),
                  onEdit: () => _editDisplayName(context, live),
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.homeWorkspaceProjectId,
                  value: live.projectId,
                  onCopy: () => _copyText(context, live.projectId),
                  showDividerBelow: true,
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.projectPrimaryPath,
                  value: live.primaryPath.isNotEmpty
                      ? live.primaryPath
                      : l10n.projectPrimaryPathNotSelected,
                  onCopy: live.primaryPath.isNotEmpty
                      ? () => _copyText(context, live.primaryPath)
                      : null,
                  trailing: live.primaryPath.isNotEmpty
                      ? TextButton(
                          onPressed: () => _openFolder(live.primaryPath),
                          child: Text(l10n.openFolder),
                        )
                      : null,
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.projectAdditionalDirectories,
                  value: live.additionalPaths.isEmpty
                      ? l10n.projectNoAdditionalDirectories
                      : l10n.homeWorkspaceProjectAdditionalDirsCount(
                          live.additionalPaths.length,
                        ),
                  onEdit: () => showProjectDetailsDialog(
                    context,
                    live,
                    sessionCount,
                  ),
                  showDividerBelow: true,
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.projectSessionCount,
                  value: '$sessionCount',
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.projectCreatedAt,
                  value: _formatTimestamp(live.createdAt),
                ),
                _ProjectSettingsInlineRow(
                  label: l10n.projectUpdatedAt,
                  value: _formatTimestamp(live.updatedAt),
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.homeWorkspaceProjectSettingsPathsHint,
            style: AppTextStyles.of(context).caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ProjectConfigDangerZone(project: live),
        ],
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context, AppProject project) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: project.display);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.projectDisplayName),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: project.localizedName(l10n)),
            ),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final display = controller.text;
    controller.dispose();
    if (saved != true || !context.mounted) return;
    final repo = context.read<SessionRepository>();
    await context.read<ChatCubit>().updateProjectMetadata(
      repo,
      project.projectId,
      display: display,
    );
  }
}

class ProjectConfigDangerZone extends StatelessWidget {
  const ProjectConfigDangerZone({required this.project, super.key});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    final name = project.localizedName(l10n);

    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteProjectSubtitle,
        body: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _confirmDelete(context, name),
            icon: Icon(
              Icons.delete_outline,
              size: AppIconSizes.md,
              color: errorColor,
            ),
            label: Text(l10n.deleteProject, style: TextStyle(color: errorColor)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: errorColor.withValues(alpha: 0.4)),
            ),
          ),
        ),
        showDividerBelow: false,
      ),
    );
  }

  void _confirmDelete(BuildContext context, String name) {
    final l10n = context.l10n;
    final repo = context.read<SessionRepository>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.deleteProject),
            const SizedBox(height: 16),
            Text(l10n.deleteProjectConfirm(name)),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  onPressed: throttledAsync(
                    'home_workspace_delete_project',
                    () async {
                      await context.read<ChatCubit>().deleteProject(
                        repo,
                        project.projectId,
                      );
                      if (!context.mounted) return;
                      Navigator.of(ctx).pop();
                      context.go('/home-v2');
                    },
                  ),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSettingsInlineRow extends StatelessWidget {
  const _ProjectSettingsInlineRow({
    required this.label,
    required this.value,
    this.onEdit,
    this.onCopy,
    this.trailing,
    this.showDividerBelow = true,
  });

  final String label;
  final String value;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget? action;
    if (onEdit != null) {
      action = TextButton(onPressed: onEdit, child: Text(l10n.edit));
    } else if (onCopy != null) {
      action = TextButton(onPressed: onCopy, child: Text(l10n.copyFolderPath));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 168,
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (trailing != null) trailing!,
              if (action != null) action,
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

String _formatTimestamp(int ms) {
  if (ms <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

void _copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.pathCopied(text)),
      duration: const Duration(seconds: 2),
    ),
  );
}

void _openFolder(String path) {
  final command = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'start'
      : 'xdg-open';
  Process.run(command, [path]);
}
