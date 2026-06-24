import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/workspace.dart';
import '../../../../services/storage/home_target_controller.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';

/// P3a (minimal): assigns one team member to a runtime target (machine). The
/// member runs on that target's workspace folders (one agent, one machine). On
/// select it emits the assigned folder paths via [onAssign]; an empty selection
/// means "inherit the workspace folders". Caller persists via
/// `SessionRepository.setMemberFolderAssignment`.
class MemberFolderAssignmentTile extends StatelessWidget {
  const MemberFolderAssignmentTile({
    required this.memberLabel,
    required this.workspace,
    required this.currentAssignment,
    required this.onAssign,
    this.requireExplicitTarget = false,
    super.key,
  });

  final String memberLabel;
  final Workspace workspace;

  /// Currently assigned folder paths (empty = inherit workspace folders).
  final List<String> currentAssignment;

  /// When true, the inherit option is hidden (mixed workspace launch).
  final bool requireExplicitTarget;

  /// Emits the folder paths for the chosen target (empty = inherit).
  final void Function(List<String> folderPaths) onAssign;

  /// Distinct target ids present in the workspace folders.
  List<String> get _workspaceTargetIds {
    final seen = <String>[];
    for (final f in workspace.folders) {
      if (!seen.contains(f.targetId)) seen.add(f.targetId);
    }
    return seen;
  }

  List<String> _pathsForTarget(String targetId) => [
    for (final f in workspace.folders)
      if (f.targetId == targetId) f.path,
  ];

  String get _currentTargetId {
    if (currentAssignment.isEmpty) return '';
    for (final f in workspace.folders) {
      if (f.path == currentAssignment.first) return f.targetId;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<HomeTargetController>();
    final current = _currentTargetId;
    return SettingsLabeledStackedRow(
      title: l10n.memberTargetAssignmentTitle,
      subtitle: l10n.memberTargetAssignmentSubtitle(memberLabel),
      showDividerBelow: true,
      body: FutureBuilder<List<RuntimeTarget>>(
        future: controller.listSelectable(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <RuntimeTarget>[];
          final labelOf = {for (final t in all) t.id: t.label};
          final targetIds = _workspaceTargetIds;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!requireExplicitTarget)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: '',
                  groupValue: current,
                  title: Text(l10n.memberTargetAssignmentInherit),
                  onChanged: (_) => onAssign(const []),
                ),
              for (final id in targetIds)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: id,
                  groupValue: current,
                  title: Text(labelOf[id] ?? id),
                  subtitle: Text(_pathsForTarget(id).join(', ')),
                  onChanged: (_) => onAssign(_pathsForTarget(id)),
                ),
            ],
          );
        },
      ),
    );
  }
}
