import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/member_instance.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/app_dialog.dart';
import 'mixed_workspace_member_placement_panel.dart';

/// Ensures every roster member is assigned to one machine before a mixed
/// workspace team session connects. Returns `true` when ready (or not needed).
Future<bool> ensureMixedWorkspaceMemberAssignments(
  BuildContext context, {
  required Workspace workspace,
  required AppSession session,
  required TeamProfile team,
  required SessionRepository repository,
}) async {
  if (!workspaceTopologyRequiresMemberAssignment(workspace.folders)) {
    return true;
  }
  final fresh = (await repository.loadSessions())
      .where((s) => s.sessionId == session.sessionId)
      .firstOrNull;
  final current = fresh ?? session;
  if (memberFolderAssignmentsComplete(
    workspaceFolders: workspace.folders,
    members: team.members,
    assignments: current.folderAssignments,
  )) {
    return true;
  }
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MixedWorkspaceMemberAssignmentDialog(
      repository: repository,
      workspace: workspace,
      session: current,
      team: team,
    ),
  );
  return confirmed == true;
}

class _MixedWorkspaceMemberAssignmentDialog extends StatefulWidget {
  const _MixedWorkspaceMemberAssignmentDialog({
    required this.repository,
    required this.workspace,
    required this.session,
    required this.team,
  });

  final SessionRepository repository;
  final Workspace workspace;
  final AppSession session;
  final TeamProfile team;

  @override
  State<_MixedWorkspaceMemberAssignmentDialog> createState() =>
      _MixedWorkspaceMemberAssignmentDialogState();
}

class _MixedWorkspaceMemberAssignmentDialogState
    extends State<_MixedWorkspaceMemberAssignmentDialog> {
  late MemberPlacementByTarget _placement;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _placement = memberPlacementFromFolderAssignments(
      workspaceFolders: widget.workspace.folders,
      members: widget.team.members,
      assignments: widget.session.folderAssignments,
    );
  }

  bool get _complete => memberPlacementComplete(
    workspaceFolders: widget.workspace.folders,
    members: widget.team.members,
    placement: _placement,
  );

  MemberFolderAssignments get _folderAssignments =>
      folderAssignmentsFromMemberPlacement(
        workspaceFolders: widget.workspace.folders,
        members: widget.team.members,
        placement: _placement,
      );

  Future<void> _save() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);
    try {
      final assignments = _folderAssignments;
      final roster = widget.team.members.where((m) => m.isValid).toList();
      final instanceIds = {
        for (final inst in expandTeamRoster(roster)) inst.instanceId,
      };
      final staleKeys = widget.session.folderAssignments.keys
          .where((id) => !instanceIds.contains(id))
          .toList(growable: false);
      for (final memberId in {...instanceIds, ...staleKeys}) {
        await widget.repository.setMemberFolderAssignment(
          widget.session.sessionId,
          memberId,
          assignments[memberId] ?? const <String>[],
        );
      }
      await widget.repository.updateWorkspaceMemberFolderAssignments(
        widget.workspace.workspaceId,
        widget.team.id,
        assignments: assignments,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      maxWidth: 820,
      maxHeight: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.mixedWorkspaceMemberAssignmentTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.mixedWorkspaceMemberAssignmentSubtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MixedWorkspaceMemberPlacementPanel(
                workspace: widget.workspace,
                members: widget.team.members,
                placement: _placement,
                onPlacementChanged: (next) => setState(() => _placement = next),
              ),
            ),
          ),
          if (!_complete)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.mixedWorkspaceMemberAssignmentIncomplete,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: !_complete || _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.mixedWorkspaceMemberAssignmentConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
