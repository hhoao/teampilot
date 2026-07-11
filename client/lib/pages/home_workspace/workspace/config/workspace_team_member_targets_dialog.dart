import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/launch_profile_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../services/launch/member_placement_save.dart';
import '../../../../widgets/app_dialog.dart';
import '../mixed_workspace_member_placement_panel.dart';
import '../../../../theme/app_text_styles.dart';

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
    final members = healMemberReplicasFromTargets(
      members: widget.team.members,
      targets: remembered,
    );
    if (remembered.isEmpty) {
      // In-memory defaults only — persist on Save via prepareMemberPlacementSave.
      _placement = defaultMemberPlacement(
        folders: workspace.folders,
        members: members,
      );
      return;
    }
    _placement = memberPlacementFromMemberTargets(
      members: members,
      targets: remembered,
    );
  }

  PreparedMemberPlacementSave get _preparedSave => prepareMemberPlacementSave(
    team: widget.team,
    folders: widget.workspace.folders,
    placement: _placement,
  );

  bool get _canSave => !_saving && _preparedSave.leadValid;

  bool get _needsMixedInit => workspaceNeedsMixedPlacementInit(
    folders: widget.workspace.folders,
    teamId: widget.team.id,
    initializedByTeam: widget.workspace.memberPlacementInitializedByTeam,
  );

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final prepared = prepareMemberPlacementSave(
        team: widget.team,
        folders: widget.workspace.folders,
        placement: _placement,
      );
      if (!prepared.leadValid) return;

      final cubit = context.read<LaunchProfileCubit>();
      await cubit.selectTeam(
        widget.team.id,
        silent: true,
        syncResources: false,
      );
      // Persist placement totals on roster.overrides.replicas (members alone
      // are runtime-only and would be dropped on the next materialize).
      await cubit.updateSelected(prepared.team);
      await widget.repository.updateWorkspaceMemberPlacement(
        widget.workspace.workspaceId,
        widget.team.id,
        targets: prepared.targets,
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
              style: AppTextStyles.of(context).mutedSm,
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
          if (!_preparedSave.leadValid || _needsMixedInit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                !_preparedSave.leadValid
                    ? l10n.mixedWorkspaceLeadPlacementInvalid
                    : l10n.mixedWorkspaceMemberAssignmentIncomplete,
                style: AppTextStyles.of(context).smColored(Theme.of(context).colorScheme.error),
              ),
            ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: !_canSave ? null : _save,
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
