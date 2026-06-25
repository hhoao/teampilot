import 'package:flutter/material.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../widgets/app_dialog.dart';
import '../mixed_workspace_member_placement_panel.dart';

/// Edits workspace + team default member→machine pins (new sessions only).
Future<bool?> showWorkspaceTeamMemberTargetsDialog(
  BuildContext context, {
  required SessionRepository repository,
  required Workspace workspace,
  required TeamProfile team,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _WorkspaceTeamMemberTargetsDialog(
      repository: repository,
      workspace: workspace,
      team: team,
    ),
  );
}

class _WorkspaceTeamMemberTargetsDialog extends StatefulWidget {
  const _WorkspaceTeamMemberTargetsDialog({
    required this.repository,
    required this.workspace,
    required this.team,
  });

  final SessionRepository repository;
  final Workspace workspace;
  final TeamProfile team;

  @override
  State<_WorkspaceTeamMemberTargetsDialog> createState() =>
      _WorkspaceTeamMemberTargetsDialogState();
}

class _WorkspaceTeamMemberTargetsDialogState
    extends State<_WorkspaceTeamMemberTargetsDialog> {
  late MemberPlacementByTarget _placement;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _syncFromWorkspace(widget.workspace);
  }

  void _syncFromWorkspace(Workspace workspace) {
    final remembered = rememberedMemberTargets(
      workspace.memberTargetsByTeam,
      widget.team.id,
    );
    _placement = memberPlacementFromMemberTargets(
      members: widget.team.members,
      targets: remembered,
    );
  }

  bool get _complete => memberPlacementComplete(
    workspaceFolders: widget.workspace.folders,
    members: widget.team.members,
    placement: _placement,
  );

  MemberTargetAssignments get _memberTargets =>
      memberTargetsFromMemberPlacement(
        workspaceFolders: widget.workspace.folders,
        members: widget.team.members,
        placement: _placement,
      );

  Future<void> _save() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateWorkspaceMemberTargets(
        widget.workspace.workspaceId,
        widget.team.id,
        targets: _memberTargets,
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
                    : Text(l10n.workspaceMemberTargetsSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
