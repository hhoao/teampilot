import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/app_dialog.dart';
import 'config/member_folder_assignment_tile.dart';

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
  late Map<String, List<String>> _draft;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = {
      for (final e in widget.session.folderAssignments.entries)
        e.key: List<String>.from(e.value),
    };
  }

  bool get _complete => memberFolderAssignmentsComplete(
    workspaceFolders: widget.workspace.folders,
    members: widget.team.members,
    assignments: _draft,
  );

  Future<void> _save() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);
    try {
      for (final member in widget.team.members) {
        if (!member.isValid) continue;
        final paths = _draft[member.id] ?? const <String>[];
        await widget.repository.setMemberFolderAssignment(
          widget.session.sessionId,
          member.id,
          paths,
        );
      }
      await widget.repository.updateWorkspaceMemberFolderAssignments(
        widget.workspace.workspaceId,
        widget.team.id,
        assignments: _draft,
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
    final members = widget.team.members.where((m) => m.isValid).toList();
    return AppDialog(
      maxWidth: 680,
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
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final member in members)
                  MemberFolderAssignmentTile(
                    memberLabel: member.name.isEmpty
                        ? l10n.memberName
                        : member.name,
                    workspace: widget.workspace,
                    currentAssignment: _draft[member.id] ?? const [],
                    requireExplicitTarget: true,
                    onAssign: (paths) {
                      setState(() {
                        if (paths.isEmpty) {
                          _draft.remove(member.id);
                        } else {
                          _draft[member.id] = paths;
                        }
                      });
                    },
                  ),
              ],
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
