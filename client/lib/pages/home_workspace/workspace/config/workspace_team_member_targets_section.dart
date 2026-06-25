import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/chat_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/member_instance.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_folder.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'workspace_team_member_targets_dialog.dart';

/// Summary card for workspace + team member→machine defaults. Opens a dialog to edit.
class WorkspaceTeamMemberTargetsSection extends StatelessWidget {
  const WorkspaceTeamMemberTargetsSection({
    required this.workspace,
    required this.team,
    super.key,
  });

  final Workspace workspace;
  final TeamProfile team;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (w) => w.workspaceId == workspace.workspaceId,
        orElse: () => workspace,
      ),
    );
    final targets = rememberedMemberTargets(
      live.memberTargetsByTeam,
      team.id,
    );
    final roster = team.members.where((m) => m.isValid).toList();
    final instances = expandTeamRoster(roster);
    final total = instances.length;
    final placed = _placedInstanceCount(
      workspaceFolders: live.folders,
      instances: instances,
      targets: targets,
    );
    final complete = memberTargetsComplete(
      workspaceFolders: live.folders,
      members: team.members,
      targets: targets,
    );

    final subtitle = total > 0 && !complete
        ? '${l10n.workspaceMemberTargetsSectionSubtitle}\n'
            '${l10n.mixedWorkspaceMemberPlacementProgress(placed, total)}'
        : l10n.workspaceMemberTargetsSectionSubtitle;

    return SettingsSurfaceCard(
      child: SettingsLabeledRow(
        title: l10n.workspaceMemberTargetsSectionTitle,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AssignmentStatusChip(
              complete: complete,
              placed: placed,
              total: total,
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => _openAssignDialog(context, live),
              child: Text(l10n.workspaceMemberTargetsAssignAction),
            ),
          ],
        ),
        showDividerBelow: false,
      ),
    );
  }

  Future<void> _openAssignDialog(BuildContext context, Workspace live) async {
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    final saved = await showWorkspaceTeamMemberTargetsDialog(
      context,
      repository: repo,
      workspace: live,
      team: team,
    );
    if (saved == true && context.mounted) {
      await chat.loadWorkspaceData(repo);
    }
  }
}

int _placedInstanceCount({
  required List<WorkspaceFolder> workspaceFolders,
  required List<MemberInstance> instances,
  required MemberTargetAssignments targets,
}) {
  var placed = 0;
  for (final instance in instances) {
    final targetId = memberTargetForInstanceId(targets, instance.instanceId);
    if (targetId != null &&
        folderPathsForTarget(workspaceFolders, targetId).isNotEmpty) {
      placed++;
    }
  }
  return placed;
}

class _AssignmentStatusChip extends StatelessWidget {
  const _AssignmentStatusChip({
    required this.complete,
    required this.placed,
    required this.total,
  });

  final bool complete;
  final int placed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = complete
        ? (
            l10n.workspaceMemberTargetsAssigned,
            Icons.check_circle_outline,
            cs.primary,
          )
        : placed > 0
        ? (
            l10n.workspaceMemberTargetsPartiallyAssigned,
            Icons.pending_outlined,
            cs.tertiary,
          )
        : (
            l10n.workspaceMemberTargetsUnassigned,
            Icons.error_outline,
            cs.error,
          );

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
