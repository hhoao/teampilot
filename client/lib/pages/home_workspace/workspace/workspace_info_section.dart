import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../widgets/workspace_topology_chip.dart';
import '../../../utils/workspace_display_name.dart';
import '../workspace_actions.dart';
import 'config/workspace_folders_section.dart';
import 'config/workspace_team_member_targets_section.dart';
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
          TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpSectionHeader(
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
                ),
                _WorkspaceSettingsInlineRow(
                  label: l10n.workspaceTypeLabel,
                  valueWidget: Align(
                    alignment: Alignment.centerLeft,
                    child: WorkspaceTopologyChip(
                      topology: workspaceTopologyOf(live.folders),
                    ),
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
          WorkspaceFoldersSection(workspace: live, lockTargets: true),
          // Placement is configured for all topologies; section lists teams that
          // already have remembered targets (local/remote/mixed).
          const SizedBox(height: 12),
          _WorkspaceMemberTargetsSections(workspace: live),
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

    return TpCard.outlined(
      child: TpPreferenceStack(
        title: l10n.dangerZone,
        subtitle: l10n.deleteWorkspaceSubtitle,
        body: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => confirmDeleteWorkspace(context, workspace),
            icon: Icon(
              Icons.delete_outline,
              size: context.tpIconSizes.md,
              color: errorColor,
            ),
            label: Text(
              l10n.deleteWorkspace,
              style: TpTextStyles.of(context).mdColored(errorColor),
            ),
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
    this.value = '',
    this.valueWidget,
    this.onEdit,
    this.onCopy,
    this.showDividerBelow = true,
  }) : trailing = null;

  final String label;
  final String value;
  final Widget? valueWidget;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

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
                  style: TpTextStyles.of(context).mdMediumColored(cs.onSurfaceVariant),
                ),
              ),
              Expanded(
                child:
                    valueWidget ??
                    Text(
                      value,
                      style: TpTextStyles.of(context).mdMedium,
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

class _WorkspaceMemberTargetsSections extends StatelessWidget {
  const _WorkspaceMemberTargetsSections({required this.workspace});

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final launchProfiles = context.watch<LaunchProfileCubit>();
    final teamIds = workspace.memberTargetsByTeam.keys
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (teamIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final teamId in teamIds) ...[
          Builder(
            builder: (context) {
              final profile = launchProfiles.byId(teamId);
              if (profile is! TeamProfile) return const SizedBox.shrink();
              return WorkspaceTeamMemberTargetsSection(
                workspace: workspace,
                team: profile,
              );
            },
          ),
          const SizedBox(height: 12),
        ],
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
