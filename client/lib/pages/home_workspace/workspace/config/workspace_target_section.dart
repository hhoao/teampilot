import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/chat_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/workspace.dart';
import '../../../../repositories/session_repository.dart';
import '../../../../services/storage/home_target_controller.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';

/// Per-workspace runtime target picker (P2 project-remote): chooses the machine
/// (local / wsl:* / ssh:*) a workspace's folders live and run on. Writes
/// `folders[].targetId` via [SessionRepository.setWorkspaceTarget]; unlike the
/// home picker it is not platform-scoped (a workspace may target any machine).
class WorkspaceTargetSection extends StatefulWidget {
  const WorkspaceTargetSection({required this.workspace, super.key});

  final Workspace workspace;

  @override
  State<WorkspaceTargetSection> createState() => _WorkspaceTargetSectionState();
}

class _WorkspaceTargetSectionState extends State<WorkspaceTargetSection> {
  late Future<List<RuntimeTarget>> _targets;
  bool _switching = false;

  String get _currentId => widget.workspace.folders.isEmpty
      ? RuntimeTarget.localId
      : widget.workspace.folders.first.targetId;

  @override
  void initState() {
    super.initState();
    _targets = context.read<HomeTargetController>().listSelectable();
  }

  Future<void> _select(String id) async {
    if (_switching || id == _currentId) return;
    setState(() => _switching = true);
    final repo = context.read<SessionRepository>();
    final chat = context.read<ChatCubit>();
    try {
      await repo.setWorkspaceTarget(widget.workspace.workspaceId, id);
      await chat.loadWorkspaceData(repo);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroupHeader(title: l10n.workspaceTargetTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              l10n.workspaceTargetSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          FutureBuilder<List<RuntimeTarget>>(
            future: _targets,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                );
              }
              final options = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final t in options)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: t.id,
                      groupValue: _currentId,
                      title: Text(t.label),
                      subtitle: Text(t.id),
                      onChanged: _switching || t.id == _currentId
                          ? null
                          : (id) {
                              if (id != null) _select(id);
                            },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
