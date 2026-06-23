import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/workspace_display_name.dart';
import '../../../widgets/workspace_details_dialog.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../../../services/io/system_folder_opener.dart';
import '../workspace_actions.dart';
import 'config/workspace_target_section.dart';
import 'workspace_icon_settings_row.dart';

/// Workspace basic settings + danger zone (same layout as [TeamInfoSection]).
class WorkspaceInfoSection extends StatelessWidget {
  const WorkspaceInfoSection({required this.workspace, super.key});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (p) => p.workspaceId == workspace.workspaceId,
        orElse: () => workspace,
      ),
    );
    final sessionCount = context.select<ChatCubit, int>(
      (c) => c.state.sessions
          .where((s) => s.workspaceId == live.workspaceId)
          .length,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceTargetSection(workspace: live),
          const SizedBox(height: 12),
          SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupHeader(
                  title: l10n.homeWorkspaceWorkspaceSettingsBasicInfo,
                ),
                WorkspaceIconSettingsRow(workspace: live),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceDisplayName,
                  value: live.localizedName(l10n),
                  onEdit: () => showRenameWorkspaceDialog(
                    context,
                    live,
                    title: l10n.workspaceDisplayName,
                  ),
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.homeWorkspaceWorkspaceId,
                  value: live.workspaceId,
                  onCopy: () => _copyText(context, live.workspaceId),
                  showDividerBelow: true,
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspacePrimaryPath,
                  value: live.firstFolderPath.isNotEmpty
                      ? live.firstFolderPath
                      : l10n.workspacePrimaryPathNotSelected,
                  onCopy: live.firstFolderPath.isNotEmpty
                      ? () => _copyText(context, live.firstFolderPath)
                      : null,
                  trailing: live.firstFolderPath.isNotEmpty
                      ? TextButton(
                          onPressed: () => _openFolder(live.firstFolderPath),
                          child: Text(l10n.openFolder),
                        )
                      : null,
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceAdditionalDirectories,
                  value: live.extraFolderPaths.isEmpty
                      ? l10n.workspaceNoAdditionalDirectories
                      : l10n.homeWorkspaceWorkspaceAdditionalDirsCount(
                          live.extraFolderPaths.length,
                        ),
                  onEdit: () => showWorkspaceDetailsDialog(
                    context,
                    live,
                    sessionCount,
                  ),
                  showDividerBelow: true,
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceSessionCount,
                  value: '$sessionCount',
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceCreatedAt,
                  value: _formatTimestamp(live.createdAt),
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceUpdatedAt,
                  value: _formatTimestamp(live.updatedAt),
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.homeWorkspaceWorkspaceSettingsPathsHint,
            style: AppTextStyles.of(context).caption.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          WorkspaceConfigDangerZone(workspace: live),
        ],
      ),
    );
  }
}

class WorkspaceConfigDangerZone extends StatelessWidget {
  const WorkspaceConfigDangerZone({required this.workspace, super.key});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;

    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteWorkspaceSubtitle,
        body: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => confirmDeleteWorkspace(context, workspace),
            icon: Icon(
              Icons.delete_outline,
              size: context.appIconSizes.md,
              color: errorColor,
            ),
            label: Text(l10n.deleteWorkspace, style: TextStyle(color: errorColor)),
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

class _WorkspaceSettingsInlineRow extends StatelessWidget {
  const _WorkspaceSettingsInlineRow({
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
