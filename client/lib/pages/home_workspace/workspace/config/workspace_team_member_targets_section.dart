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
    final targets = rememberedMemberTargets(live.memberTargetsByTeam, team.id);
    final roster = team.members.where((m) => m.isValid).toList();
    final instances = expandTeamRoster(roster);
    final total = instances.length;
    final placed = _placedInstanceCount(
      workspaceFolders: live.folders,
      instances: instances,
      targets: targets,
    );
    final needsInit = workspaceNeedsMixedPlacementInit(
      folders: live.folders,
      teamId: team.id,
      initializedByTeam: live.memberPlacementInitializedByTeam,
    );
    final status = workspaceMemberTargetsStatus(
      needsMixedInit: needsInit,
      placed: placed,
      total: total,
    );

    final subtitle = !needsInit && total > 0 && placed < total
        ? '${l10n.workspaceMemberTargetsSectionSubtitle}\n'
              '${l10n.mixedWorkspaceMemberPlacementProgress(placed, total)}'
        : needsInit
        ? '${l10n.workspaceMemberTargetsSectionSubtitle}\n'
              '${l10n.mixedWorkspaceMemberAssignmentIncomplete}'
        : l10n.workspaceMemberTargetsSectionSubtitle;

    return SettingsSurfaceCard(
      child: SettingsLabeledRow(
        title: l10n.workspaceMemberTargetsSectionTitle,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AssignmentStatusChip(status: status),
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

/// Chip / summary status for the workspace member-targets section.
enum WorkspaceMemberTargetsStatus {
  /// Mixed workspace has not confirmed Machines yet.
  needsConfirmation,

  /// Placement initialized (or non-mixed) and every instance has a pin.
  assigned,

  /// Placement initialized but some instances lack pins (stale drift).
  partiallyAssigned,
}

/// Derives section chip status from mixed-init flag and placement counts.
///
/// After init, incomplete pins are soft (partial), not a hard unassigned failure.
WorkspaceMemberTargetsStatus workspaceMemberTargetsStatus({
  required bool needsMixedInit,
  required int placed,
  required int total,
}) {
  if (needsMixedInit) return WorkspaceMemberTargetsStatus.needsConfirmation;
  if (total > 0 && placed < total) {
    return WorkspaceMemberTargetsStatus.partiallyAssigned;
  }
  return WorkspaceMemberTargetsStatus.assigned;
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
  const _AssignmentStatusChip({required this.status});

  final WorkspaceMemberTargetsStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (status) {
      WorkspaceMemberTargetsStatus.assigned => (
        l10n.workspaceMemberTargetsAssigned,
        Icons.check_circle_outline,
        cs.primary,
      ),
      WorkspaceMemberTargetsStatus.partiallyAssigned => (
        l10n.workspaceMemberTargetsPartiallyAssigned,
        Icons.pending_outlined,
        cs.tertiary,
      ),
      WorkspaceMemberTargetsStatus.needsConfirmation => (
        l10n.workspaceMemberTargetsNeedsConfirmation,
        Icons.error_outline,
        cs.error,
      ),
    };

    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label, style: labelStyle),
          ],
        ),
      ),
    );
  }
}
