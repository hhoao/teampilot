import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/chat_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_folder.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
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
  State<WorkspaceFoldersSection> createState() => _WorkspaceFoldersSectionState();
}

class _WorkspaceFoldersSectionState extends State<WorkspaceFoldersSection> {
  var _saving = false;

  Future<void> _persist(List<WorkspaceFolder> folders) async {
    if (_saving) return;
    final valid = folders.where((f) => f.path.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    setState(() => _saving = true);
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    try {
      await repo.updateWorkspaceFolders(widget.workspace.workspaceId, valid);
      await chat.loadWorkspaceData(repo);
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

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: LinearProgressIndicator(),
            ),
          SettingsLabeledStackedRow(
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
              onChanged: _persist,
            ),
          ),
        ],
      ),
    );
  }
}
