import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../../cubits/chat_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_folder.dart';
import '../../../../models/workspace_topology.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../repositories/ssh_profile_repository.dart';
import '../../../../services/storage/home_target_controller.dart';
import '../../../../services/workspace/target_liveness.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import '../../../../widgets/workspace/workspace_dead_target_remap_dialog.dart';
import '../../../../widgets/workspace_folders_editor.dart';

/// Per-workspace directory + machine editor (local / project-remote / mixed).
class WorkspaceFoldersSection extends StatefulWidget {
  const WorkspaceFoldersSection({
    required this.workspace,
    this.lockTargets = false,
    super.key,
  });

  final Workspace workspace;

  /// Personal launch identity cannot reassign folder machines.
  final bool lockTargets;

  @override
  State<WorkspaceFoldersSection> createState() =>
      _WorkspaceFoldersSectionState();
}

class _WorkspaceFoldersSectionState extends State<WorkspaceFoldersSection> {
  var _saving = false;
  Set<String> _deadTargetIds = const {};
  List<String>? _deadCheckKey;

  TargetLiveness _liveness(BuildContext context) => DefaultTargetLiveness(
    sshProfiles: context.read<SshProfileRepository>(),
  );

  void _ensureDeadTargetsChecked(List<WorkspaceFolder> folders) {
    final key = workspaceTargetIds(folders);
    if (_deadCheckKey != null && listEquals(_deadCheckKey, key)) return;
    _deadCheckKey = List<String>.from(key);
    _loadDeadTargets(key);
  }

  Future<void> _loadDeadTargets(List<String> targetIds) async {
    final liveness = _liveness(context);
    final dead = <String>{};
    for (final id in targetIds) {
      if (!await liveness.isAlive(id)) {
        dead.add(id);
      }
    }
    if (!mounted) return;
    if (_deadCheckKey != null && listEquals(_deadCheckKey, targetIds)) {
      setState(() => _deadTargetIds = dead);
    }
  }

  void _invalidateDeadTargetCache() {
    _deadCheckKey = null;
    _deadTargetIds = const {};
  }

  Future<void> _persist(List<WorkspaceFolder> folders) async {
    if (_saving) return;
    final valid = folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    setState(() => _saving = true);
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    try {
      await repo.updateWorkspaceFolders(widget.workspace.workspaceId, valid);
      chat.invalidateWorkspaceProvision(
        widget.workspace.copyWith(folders: valid),
      );
      await chat.loadWorkspaceData(repo);
      _invalidateDeadTargetCache();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remapDeadTarget(String fromTargetId) async {
    if (_saving) return;
    setState(() => _saving = true);
    final liveness = _liveness(context);
    final homeTarget = context.read<HomeTargetController>();
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    try {
      final selectable = await homeTarget.listSelectable();
      if (!mounted) return;
      final to = await showWorkspaceDeadTargetRemapDialog(
        context: context,
        fromTargetId: fromTargetId,
        deadTargetIds: _deadTargetIds.toList(),
        selectable: selectable,
        liveness: liveness,
      );
      if (to == null || !mounted) return;

      final updated = await repo.remapWorkspaceTarget(
        widget.workspace.workspaceId,
        fromTargetId: fromTargetId,
        toTargetId: to,
        liveness: liveness,
      );
      chat.invalidateWorkspaceProvision(updated);
      await chat.loadWorkspaceData(repo);
      _invalidateDeadTargetCache();
    } on Object {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.workspaceDeadTargetRemapFailed,
          variant: AppToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final live = context.select<ChatCubit, Workspace>(
      (c) => c.state.workspaces.firstWhere(
        (w) => w.workspaceId == widget.workspace.workspaceId,
        orElse: () => widget.workspace,
      ),
    );
    final folders = live.folders.isEmpty
        ? [const WorkspaceFolder(path: '')]
        : live.folders;

    _ensureDeadTargetsChecked(live.folders);

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: LinearProgressIndicator(),
            ),
          TpPreferenceStack(
            title: l10n.workspaceFoldersSectionTitle,
            subtitle: workspaceFoldersEditorHint(
              l10n,
              live.folders,
              lockTargets: widget.lockTargets,
            ),
            showDividerBelow: false,
            body: WorkspaceFoldersEditor(
              folders: folders,
              enabled: !_saving,
              lockTargets: widget.lockTargets,
              deadTargetIds: _deadTargetIds,
              onRemapDeadTarget: _remapDeadTarget,
              onChanged: _persist,
            ),
          ),
        ],
      ),
    );
  }
}
