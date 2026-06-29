import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/workspace_display_name.dart';
import '../../../widgets/workspace_details_dialog.dart';
import '../../../widgets/settings/workspace_hub_shell.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../workspace_actions.dart';
import 'workspace_section.dart';
import 'workspace_icon_settings_row.dart';

/// Apifox-style workspace settings: section nav + scrollable detail cards.
class WorkspaceSettingsView extends StatefulWidget {
  const WorkspaceSettingsView({required this.workspace, super.key});

  final Workspace workspace;

  static const double navWidth = 220;

  @override
  State<WorkspaceSettingsView> createState() =>
      _WorkspaceSettingsViewState();
}

class _WorkspaceSettingsViewState
    extends State<WorkspaceSettingsView> {
  WorkspaceSettingsSection _section = WorkspaceSettingsSection.basic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final workspace = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (p) => p.workspaceId == widget.workspace.workspaceId,
        orElse: () => widget.workspace,
      ),
    );
    final sessionCount = context.select<ChatCubit, int>(
      (c) => c.state.sessions
          .where((s) => s.workspaceId == workspace.workspaceId)
          .length,
    );

    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: WorkspaceSettingsView.navWidth,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: WorkspaceHubNavList(
              sidebarStyle: true,
              shrinkWrap: true,
              entries: [
                WorkspaceHubEntry(
                  title: l10n.homeWorkspaceWorkspaceSettingsSectionBasic,
                  icon: Icons.tune_outlined,
                  selected: _section == WorkspaceSettingsSection.basic,
                  density: WorkspaceHubNavDensity.relaxed,
                  onTap: () =>
                      setState(() => _section = WorkspaceSettingsSection.basic),
                ),
                WorkspaceHubEntry(
                  title: l10n.dangerZone,
                  icon: Icons.warning_amber_outlined,
                  selected: _section == WorkspaceSettingsSection.danger,
                  density: WorkspaceHubNavDensity.relaxed,
                  onTap: () =>
                      setState(() => _section = WorkspaceSettingsSection.danger),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WorkspaceHubTitleBar(
                  compact: true,
                  title: l10n.homeWorkspaceWorkspaceSettings,
                  subtitle: workspace.localizedName(l10n),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    child: switch (_section) {
                      WorkspaceSettingsSection.basic =>
                        _WorkspaceSettingsBasicSection(
                          workspace: workspace,
                          sessionCount: sessionCount,
                        ),
                      WorkspaceSettingsSection.danger =>
                        _WorkspaceSettingsDangerSection(workspace: workspace),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSettingsBasicSection extends StatelessWidget {
  const _WorkspaceSettingsBasicSection({
    required this.workspace,
    required this.sessionCount,
  });

  final Workspace workspace;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroupHeader(
                title: l10n.homeWorkspaceWorkspaceSettingsBasicInfo,
              ),
              WorkspaceIconSettingsRow(workspace: workspace),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspaceDisplayName,
                value: workspace.localizedName(l10n),
                onEdit: () => showRenameWorkspaceDialog(
                  context,
                  workspace,
                  title: l10n.workspaceDisplayName,
                ),
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.homeWorkspaceWorkspaceId,
                value: workspace.workspaceId,
                onCopy: () => _copyText(context, workspace.workspaceId),
                showDividerBelow: true,
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspacePrimaryPath,
                value: workspace.firstFolderPath.isNotEmpty
                    ? workspace.firstFolderPath
                    : l10n.workspacePrimaryPathNotSelected,
                onCopy: workspace.firstFolderPath.isNotEmpty
                    ? () => _copyText(context, workspace.firstFolderPath)
                    : null,
                trailing: workspace.firstFolderPath.isNotEmpty
                    ? TextButton(
                        onPressed: () => _openFolder(workspace.firstFolderPath),
                        child: Text(l10n.openFolder),
                      )
                    : null,
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspaceAdditionalDirectories,
                value: workspace.extraFolderPaths.isEmpty
                    ? l10n.workspaceNoAdditionalDirectories
                    : l10n.homeWorkspaceWorkspaceAdditionalDirsCount(
                        workspace.extraFolderPaths.length,
                      ),
                onEdit: () =>
                    showWorkspaceDetailsDialog(context, workspace, sessionCount),
                showDividerBelow: true,
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspaceSessionCount,
                value: '$sessionCount',
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspaceCreatedAt,
                value: _formatTimestamp(workspace.createdAt),
              ),
              _WorkspaceSettingsInlineRow(
                label: l10n.workspaceUpdatedAt,
                value: _formatTimestamp(workspace.updatedAt),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.homeWorkspaceWorkspaceSettingsPathsHint,
          style: styles.caption.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WorkspaceSettingsDangerSection extends StatelessWidget {
  const _WorkspaceSettingsDangerSection({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteWorkspaceSubtitle,
        showDividerBelow: false,
        body: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => confirmDeleteWorkspace(context, workspace),
            child: Text(l10n.deleteWorkspace),
          ),
        ),
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
                child: Text(
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
  final command = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'start'
      : 'xdg-open';
  Process.run(command, [path]);
}
