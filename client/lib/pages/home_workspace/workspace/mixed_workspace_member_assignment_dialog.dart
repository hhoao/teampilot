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
/// workspace team session connects.
///
/// Returns the disk-backed [AppSession] when ready, or `null` when cancelled /
/// not needed because the workspace is not mixed.
Future<AppSession?> ensureMixedWorkspaceMemberAssignments(
  BuildContext context, {
  required Workspace workspace,
  required AppSession session,
  required TeamProfile team,
  required SessionRepository repository,
}) async {
  if (!workspaceTopologyRequiresMemberAssignment(workspace.folders)) {
    return _reloadSession(repository, session);
  }
  var current = await _reloadSession(repository, session);
  if (memberTargetsComplete(
    workspaceFolders: workspace.folders,
    members: team.members,
    targets: current.memberTargets,
  )) {
    return current;
  }
  if (!context.mounted) return null;
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
  if (confirmed != true) return null;
  return _reloadSession(repository, session);
}

Future<AppSession> _reloadSession(
  SessionRepository repository,
  AppSession session,
) async {
  final fresh = (await repository.loadSessions())
      .where((s) => s.sessionId == session.sessionId)
      .firstOrNull;
  return fresh ?? session;
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
    _placement = memberPlacementFromMemberTargets(
      members: widget.team.members,
      targets: widget.session.memberTargets,
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
      final targets = _memberTargets;
      final roster = widget.team.members.where((m) => m.isValid).toList();
      final instanceIds = {
        for (final inst in expandTeamRoster(roster)) inst.instanceId,
      };
      final staleKeys = widget.session.memberTargets.keys
          .where((id) => !instanceIds.contains(id))
          .toList(growable: false);
      await widget.repository.replaceMemberTargets(
        widget.session.sessionId,
        targets: targets,
        instanceIdsToClear: {...instanceIds, ...staleKeys},
      );
      await widget.repository.updateWorkspaceMemberTargets(
        widget.workspace.workspaceId,
        widget.team.id,
        targets: targets,
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
