import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../repositories/session_repository.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/project_display_name.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/project_details_dialog.dart';
import '../../../widgets/settings/workspace_hub_shell.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import 'home_workspace_project_section.dart';
import 'project_icon_settings_row.dart';

/// Apifox-style project settings: section nav + scrollable detail cards.
class HomeWorkspaceProjectSettingsView extends StatefulWidget {
  const HomeWorkspaceProjectSettingsView({required this.project, super.key});

  final AppProject project;

  static const double navWidth = 220;

  @override
  State<HomeWorkspaceProjectSettingsView> createState() =>
      _HomeWorkspaceProjectSettingsViewState();
}

class _HomeWorkspaceProjectSettingsViewState
    extends State<HomeWorkspaceProjectSettingsView> {
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
            width: HomeWorkspaceProjectSettingsView.navWidth,
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
                onEdit: () => _editDisplayName(context, project),
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

  Future<void> _editDisplayName(
    BuildContext context,
    AppProject project,
  ) async {
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

class _ProjectSettingsDangerSection extends StatelessWidget {
  const _ProjectSettingsDangerSection({required this.project});

  final AppProject project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final name = project.localizedName(l10n);

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
            onPressed: () => _confirmDelete(context, name),
            child: Text(l10n.deleteProject),
          ),
        ),
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
