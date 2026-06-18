import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/project_display_name.dart';
import '../../../widgets/project_details_dialog.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../../../services/io/system_folder_opener.dart';
import '../home_workspace_project_actions.dart';
import 'project_icon_settings_row.dart';

/// Project basic settings + danger zone (same layout as [TeamInfoSection]).
class ProjectInfoSection extends StatelessWidget {
  const ProjectInfoSection({required this.project, super.key});

  final Workspace project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = context.select<ChatCubit, Workspace>(
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
                  onEdit: () => showRenameWorkspaceDialog(
                    context,
                    live,
                    title: l10n.projectDisplayName,
                  ),
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
}

class ProjectConfigDangerZone extends StatelessWidget {
  const ProjectConfigDangerZone({required this.project, super.key});

  final Workspace project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;

    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteProjectSubtitle,
        body: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => confirmDeleteWorkspace(context, project),
            icon: Icon(
              Icons.delete_outline,
              size: context.appIconSizes.md,
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
  AppToast.show(
    context,
    message: context.l10n.pathCopied(text),
    variant: AppToastVariant.success,
  );
}

void _openFolder(String path) {
  SystemFolderOpener().reveal(path);
}
