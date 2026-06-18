import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/project_display_name.dart';
import '../../../widgets/project_details_dialog.dart';
import '../../../widgets/settings/workspace_hub_shell.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../home_workspace_project_actions.dart';
import 'home_workspace_project_section.dart';
import 'project_icon_settings_row.dart';

/// Apifox-style project settings: section nav + scrollable detail cards.
class WorkspaceSettingsView extends StatefulWidget {
  const WorkspaceSettingsView({required this.project, super.key});

  final AppProject project;

  static const double navWidth = 220;

  @override
  State<WorkspaceSettingsView> createState() =>
      _WorkspaceSettingsViewState();
}

class _WorkspaceSettingsViewState
    extends State<WorkspaceSettingsView> {
  ProjectSettingsSection _section = ProjectSettingsSection.basic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final project = context.select<ChatCubit, AppProject>(
      (c) => c.state.projects.firstWhere(
        (p) => p.projectId == widget.project.projectId,
        orElse: () => widget.project,
      ),
    );
    final sessionCount = context.select<ChatCubit, int>(
      (c) => c.state.sessions
          .where((s) => s.projectId == project.projectId)
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
                  title: l10n.homeWorkspaceProjectSettingsSectionBasic,
                  icon: Icons.tune_outlined,
                  selected: _section == ProjectSettingsSection.basic,
                  density: WorkspaceHubNavDensity.relaxed,
                  onTap: () =>
                      setState(() => _section = ProjectSettingsSection.basic),
                ),
                WorkspaceHubEntry(
                  title: l10n.dangerZone,
                  icon: Icons.warning_amber_outlined,
                  selected: _section == ProjectSettingsSection.danger,
                  density: WorkspaceHubNavDensity.relaxed,
                  onTap: () =>
                      setState(() => _section = ProjectSettingsSection.danger),
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
                  title: l10n.homeWorkspaceProjectSettings,
                  subtitle: project.localizedName(l10n),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    child: switch (_section) {
                      ProjectSettingsSection.basic =>
                        _ProjectSettingsBasicSection(
                          project: project,
                          sessionCount: sessionCount,
                        ),
                      ProjectSettingsSection.danger =>
                        _ProjectSettingsDangerSection(project: project),
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

class _ProjectSettingsBasicSection extends StatelessWidget {
  const _ProjectSettingsBasicSection({
    required this.project,
    required this.sessionCount,
  });

  final AppProject project;
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
                title: l10n.homeWorkspaceProjectSettingsBasicInfo,
              ),
              ProjectIconSettingsRow(project: project),
              _ProjectSettingsInlineRow(
                label: l10n.projectDisplayName,
                value: project.localizedName(l10n),
                onEdit: () => showRenameWorkspaceDialog(
                  context,
                  project,
                  title: l10n.projectDisplayName,
                ),
              ),
              _ProjectSettingsInlineRow(
                label: l10n.homeWorkspaceProjectId,
                value: project.projectId,
                onCopy: () => _copyText(context, project.projectId),
                showDividerBelow: true,
              ),
              _ProjectSettingsInlineRow(
                label: l10n.projectPrimaryPath,
                value: project.primaryPath.isNotEmpty
                    ? project.primaryPath
                    : l10n.projectPrimaryPathNotSelected,
                onCopy: project.primaryPath.isNotEmpty
                    ? () => _copyText(context, project.primaryPath)
                    : null,
                trailing: project.primaryPath.isNotEmpty
                    ? TextButton(
                        onPressed: () => _openFolder(project.primaryPath),
                        child: Text(l10n.openFolder),
                      )
                    : null,
              ),
              _ProjectSettingsInlineRow(
                label: l10n.projectAdditionalDirectories,
                value: project.additionalPaths.isEmpty
                    ? l10n.projectNoAdditionalDirectories
                    : l10n.homeWorkspaceProjectAdditionalDirsCount(
                        project.additionalPaths.length,
                      ),
                onEdit: () =>
                    showProjectDetailsDialog(context, project, sessionCount),
                showDividerBelow: true,
              ),
              _ProjectSettingsInlineRow(
                label: l10n.projectSessionCount,
                value: '$sessionCount',
              ),
              _ProjectSettingsInlineRow(
                label: l10n.projectCreatedAt,
                value: _formatTimestamp(project.createdAt),
              ),
              _ProjectSettingsInlineRow(
                label: l10n.projectUpdatedAt,
                value: _formatTimestamp(project.updatedAt),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.homeWorkspaceProjectSettingsPathsHint,
          style: styles.caption.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ProjectSettingsDangerSection extends StatelessWidget {
  const _ProjectSettingsDangerSection({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return SettingsSurfaceCard(
      child: SettingsLabeledStackedRow(
        title: l10n.dangerZone,
        subtitle: l10n.deleteProjectSubtitle,
        showDividerBelow: false,
        body: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => confirmDeleteWorkspace(context, project),
            child: Text(l10n.deleteProject),
          ),
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
